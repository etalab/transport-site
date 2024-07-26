defmodule Transport.Jobs.ImportDatasetFollowersJob do
  @moduledoc """
  Import dataset followers coming from the data.gouv.fr's API.

  We *do not* create rows when a contact is a producer of a dataset
  (ie member of its organization) and the contact follows the dataset.

  We clean up contacts following datasets for which they are a producer
  at the beginning of the job to handle:
  - contacts joining organizations
  - previous bad states.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  require Logger

  # The number of workers to run in parallel when importing followers
  @task_concurrency 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    delete_producers_following_their_datasets()

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

  def delete_producers_following_their_datasets do
    DB.DatasetFollower.base_query()
    |> join(:inner, [dataset_follower: df], c in assoc(df, :contact), as: :contact)
    |> join(:inner, [contact: c], c in assoc(c, :organizations), as: :organization)
    |> join(:inner, [dataset_follower: df, contact: c, organization: o], d in assoc(df, :dataset),
      on: d.organization_id == o.id,
      as: :dataset
    )
    |> DB.Repo.delete_all()
  end

  def import_dataset_followers(%DB.Dataset{id: dataset_id, datagouv_id: datagouv_id} = dataset) do
    case Datagouvfr.Client.Datasets.get_followers(datagouv_id) do
      {:ok, %{"data" => data, "next_page" => next_page}} ->
        # Pagination is not implemented yet (and shouldn't be needed soon as page_size is 500).
        # We want to know when we need to implement it.
        unless is_nil(next_page) do
          Sentry.capture_message("#{__MODULE__}: should iterate to get all followers for Dataset##{datagouv_id}")
        end

        datagouv_user_ids = Enum.map(data, & &1["follower"]["id"])

        contact_details()
        |> Map.take(datagouv_user_ids)
        |> Enum.reject(&contact_is_producer?(&1, dataset))
        |> Enum.each(fn {_, %{contact_id: contact_id}} ->
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

  def contact_is_producer?({_, %{organization_ids: contact_org_ids}}, %DB.Dataset{organization_id: dataset_org_id}) do
    dataset_org_id in contact_org_ids
  end

  @doc """
  Fetches all contact IDs, datagouv user IDs and their organization IDs for `DB.Contact`.

  Caches the result since it's pretty stable and it needs to be used by
  every worker, for every datasets.
  """
  @spec contact_details() :: %{
          binary() => %{contact_id: integer(), datagouv_user_id: binary(), organization_ids: [binary() | nil]}
        }
  def contact_details do
    Transport.Cache.fetch(
      "#{__MODULE__}:contact_details",
      fn ->
        DB.Contact.base_query()
        |> join(:left, [contact: c], o in assoc(c, :organizations), as: :organization)
        |> where([contact: c], not is_nil(c.datagouv_user_id))
        |> select([contact: c, organization: o], %{
          contact_id: c.id,
          datagouv_user_id: c.datagouv_user_id,
          organization_ids: fragment("array_agg(?)", o.id)
        })
        |> group_by([contact: c], [c.id, c.datagouv_user_id])
        |> DB.Repo.all()
        |> Map.new(&{&1.datagouv_user_id, &1})
      end,
      :timer.seconds(60)
    )
  end
end
