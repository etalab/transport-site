defmodule Transport.Jobs.MigrateHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `MigrateHistoryJob`.

  The goal is to migrate resources that have been historicized
  by the old system to the new system.
  It ignores objects that have already been backed up.
  """
  use Oban.Worker, tags: ["history"]
  require Logger
  import Ecto.Query
  alias DB.{Dataset, Repo, ResourceHistory}

  @impl Oban.Worker
  def perform(_job) do
    already_historised_urls = already_historised()

    objects_to_historise =
      all_objects()
      |> Enum.reject(&Map.has_key?(already_historised_urls, &1.href))

    Logger.debug("Dispatching #{Enum.count(objects_to_historise)} jobs")

    objects_to_historise
    |> Enum.map(&Transport.Jobs.MigrateHistoryJob.new(&1))
    |> Oban.insert_all()

    :ok
  end

  defp already_historised do
    ResourceHistory
    |> select([_], fragment("payload ->>'old_href'"))
    |> where([_], fragment("(payload ->> 'from_old_system')::boolean = true"))
    |> Repo.all()
    # Mapping into a map to search a key in logarithmic time
    |> Enum.into(%{}, &{&1, true})
  end

  defp all_objects do
    datasets = Dataset |> preload([:resources]) |> Repo.all()
    bucket_names = existing_bucket_names()

    datasets
    |> Enum.filter(&Enum.member?(bucket_names, "dataset-#{&1.datagouv_id}"))
    |> Enum.take(5)
    |> Enum.flat_map(fn dataset ->
      Logger.debug("Finding objects for #{dataset.datagouv_id}")
      Transport.History.Fetcher.history_resources(dataset)
    end)
    |> Enum.reject(&String.starts_with?(&1.metadata["url"], "https://demo-static.data.gouv.fr"))
  end

  defp existing_bucket_names do
    buckets_response = ExAws.S3.list_buckets() |> Transport.Wrapper.ExAWS.impl().request!()
    buckets_response.body.buckets |> Enum.map(& &1.name)
  end
end

defmodule Transport.Jobs.MigrateHistoryJob do
  @moduledoc """
  Job historicising a single resource
  """
  use Oban.Worker, unique: [period: 60 * 60, fields: [:args, :worker]], tags: ["history"], max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{Repo, ResourceHistory}

  #   %{
  #   href: "https://dataset-5c34c93f8b4c4104b817fb3a.cellar-c2.services.clever-cloud.com/Fichiers_GTFS_20201118T000001",
  #   is_current: false,
  #   last_modified: "2020-11-18T00:00:01.953Z",
  #   metadata: %{
  #     "content-hash" => "1111dfda713942722c5497f561e9f2f3d4caa23e01f3c26c0a5252b7e7261fcd",
  #     "end" => "2021-07-04",
  #     "format" => "GTFS",
  #     "start" => "2020-11-01",
  #     "title" => "Fichiers_GTFS",
  #     "updated-at" => "2020-11-17T10:28:05.852000",
  #     "url" => "https://static.data.gouv.fr/resources/donnees-horaires-theoriques-gtfs-du-reseau-de-transport-de-la-metropole-de-saint-etienne-stas/20201117-102502/stas.gtfs.zip"
  #   },
  #   name: "Fichiers_GTFS_20201118T000001"
  # },

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"href" => href, "metadata" => metadata, "name" => name}}) do
    Logger.info("Running MigrateHistoryJob for #{href}")

    :ok
  end
end
