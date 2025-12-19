defmodule Transport.Jobs.VisitProxyStatisticsJob do
  @moduledoc """
  This job sends emails to producers who are using the transport proxy.
  It tells them to look at their producer space to see statistics.
  """
  use Oban.Worker, max_attempts: 1
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(relevant_contacts(), fn %DB.Contact{} = contact ->
      contact
      |> save_notification()
      |> Transport.UserNotifier.visit_proxy_statistics()
      |> Transport.Mailer.deliver()
    end)
  end

  def relevant_contacts do
    DB.Resource
    |> select([r], [:url, :dataset_id])
    |> preload(dataset: [organization_object: :contacts])
    |> DB.Repo.all()
    |> Enum.filter(&DB.Resource.served_by_proxy?/1)
    |> Enum.flat_map(& &1.dataset.organization_object.contacts)
    |> Enum.uniq()
  end

  defp save_notification(%DB.Contact{id: contact_id, email: email} = contact) do
    DB.Notification.insert!(%{
      contact_id: contact_id,
      email: email,
      reason: :visit_proxy_statistics,
      role: :producer
    })

    contact
  end
end
