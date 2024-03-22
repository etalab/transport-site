defmodule Transport.Jobs.ImportDatasetFollowersJob do
  @moduledoc """
  Import dataset followers coming from the data.gouv.fr's API.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  require Logger

  # The number of workers to run in parallel when importing followers
  @task_concurrency 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    DB.Dataset.base_query()
    |> DB.Repo.all()
    |> Task.async_stream(
      &import_dataset_followers/1,
      max_concurrency: @task_concurrency,
      on_timeout: :kill_task,
      timeout: 10_000
    )
    |> Stream.run()
  end

  def import_dataset_followers(%DB.Dataset{id: dataset_id, datagouv_id: datagouv_id}) do
    case Datagouvfr.Client.Datasets.get_followers(datagouv_id) do
      {:ok, %{"data" => data, "next_page" => next_page}} ->
        unless is_nil(next_page) do
          Sentry.capture_message("#{__MODULE__}: should iterate to get all followers for Dataset##{datagouv_id}")
        end

        datagouv_user_ids = data |> Enum.map(& &1["follower"]["id"]) |> MapSet.new()

        contacts_with_datagouv_id()
        |> Enum.filter(fn %{datagouv_user_id: datagouv_user_id} ->
          MapSet.member?(datagouv_user_ids, datagouv_user_id)
        end)
        |> Enum.each(fn %{contact_id: contact_id} ->
          %DB.DatasetFollower{}
          |> DB.DatasetFollower.changeset(%{contact_id: contact_id, dataset_id: dataset_id, source: :datagouv})
          |> DB.Repo.insert!(
            conflict_target: [:dataset_id, :contact_id],
            on_conflict: :nothing
          )
        end)

      response ->
        Logger.info("Followers not found for Dataset##{datagouv_id}: #{inspect(response)}")
    end
  end

  @spec contacts_with_datagouv_id() :: %{contact_id: integer(), datagouv_user_id: binary()}
  @doc """
  Fetches all contact IDs and datagouv user IDs for `DB.Contact`.
  Caches the result since it's pretty stable and it needs to be used by
  every worker, for every datasets.
  """
  def contacts_with_datagouv_id do
    Transport.Cache.API.fetch(
      "#{__MODULE__}:contacts_with_datagouv_id",
      fn ->
        DB.Contact.base_query()
        |> where([contact: c], not is_nil(c.datagouv_user_id))
        |> select([contact: c], %{contact_id: c.id, datagouv_user_id: c.datagouv_user_id})
        |> DB.Repo.all()
        |> MapSet.new()
      end,
      :timer.seconds(60)
    )
  end
end
