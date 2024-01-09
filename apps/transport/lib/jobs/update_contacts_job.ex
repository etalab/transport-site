defmodule Transport.Jobs.UpdateContactsJob do
  @moduledoc """
  This job is in charge updating organizations for `DB.Contact` who are linked
  to a data.gouv.fr's user, using its API.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when is_nil(args) or args == %{} do
    DB.Contact.base_query()
    |> where([contact: c], not is_nil(c.datagouv_user_id))
    |> select([contact: c], c.datagouv_user_id)
    |> DB.Repo.all()
    |> Enum.chunk_every(10)
    |> Enum.with_index()
    |> Enum.map(fn {ids, index} -> new(%{contact_ids: ids}, schedule_in: index * 3) end)
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_ids" => ids}}) do
    DB.Contact.base_query()
    |> where([contact: c], c.datagouv_user_id in ^ids)
    |> DB.Repo.all()
    |> Enum.each(&update_contact/1)
  end

  defp update_contact(%DB.Contact{datagouv_user_id: datagouv_user_id} = contact) do
    # https://doc.data.gouv.fr/api/reference/#/users/get_user
    # 404 status code: User not found
    # 410 status code: User is not active or has been deleted
    case Datagouvfr.Client.User.get(datagouv_user_id) do
      {:ok, %{"organizations" => organizations}} ->
        contact
        |> DB.Contact.changeset(%{organizations: organizations})
        |> DB.Repo.update!()

      {:error, reason} when reason in [:not_found, :gone] ->
        contact
        |> DB.Contact.changeset(%{organizations: [], datagouv_user_id: nil})
        |> DB.Repo.update!()
    end
  end
end
