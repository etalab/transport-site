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
  def perform(%Oban.Job{args: args}) do
    already_historised_urls = already_historised()

    objects_to_historise =
      all_objects()
      |> Enum.reject(&Map.has_key?(already_historised_urls, &1.href))
      |> Enum.take(objects_to_process(args))

    Logger.info("Dispatching #{Enum.count(objects_to_historise)} jobs")

    objects_to_historise
    |> Enum.chunk_every(500)
    |> Enum.map(fn list -> Enum.map(list, &Transport.Jobs.MigrateHistoryJob.new(&1)) |> Oban.insert_all() end)

    :ok
  end

  defp objects_to_process(args) do
    value = Map.get(args, "limit", 10_000)

    if value < 0 do
      raise "limit should not be negative (got #{value})"
    end

    value
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

    datasets
    |> Enum.filter(&Enum.member?(Transport.S3.bucket_names(), "dataset-#{&1.datagouv_id}"))
    |> Enum.flat_map(fn dataset ->
      Logger.info("Finding objects for #{dataset.datagouv_id}")
      Transport.History.Fetcher.history_resources(dataset)
    end)
    |> Enum.reject(&String.starts_with?(&1.metadata["url"], "https://demo-static.data.gouv.fr"))
  end
end

defmodule Transport.Jobs.MigrateHistoryJob do
  @moduledoc """
  Job historicising a single resource
  """
  use Oban.Worker, unique: [period: 60 * 60, fields: [:args, :worker]], tags: ["history"], max_attempts: 3
  require Logger
  import Ecto.Query
  import Transport.Jobs.ResourceHistoryJob, only: [relevant_http_headers: 1, http_client: 0, remove_file: 1]
  alias DB.{Dataset, Repo, Resource, ResourceHistory}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"href" => href, "dataset_datagouv_id" => dataset_datagouv_id} = payload}) do
    Logger.info("Running MigrateHistoryJob for #{href}")
    url = Map.fetch!(payload["metadata"], "url")

    case {already_historised?(href), existing_resource(url, dataset_datagouv_id)} do
      {false, resource} when is_map(resource) ->
        path = download_path(resource)

        try do
          href |> download_resource(path) |> process_download(resource, payload)
        after
          remove_file(path)
        end

      {true, _} ->
        Logger.info("#{url} has already been historicized")

      {_, nil} ->
        Logger.info("Could not find a resource for #{url}")
    end

    :ok
  end

  defp process_download({:error, message}, %Resource{datagouv_id: datagouv_id}, _) do
    Logger.info("Got an error while downloading #{datagouv_id}: #{message}")
  end

  defp process_download({:ok, resource_path, headers, body}, %Resource{datagouv_id: datagouv_id} = resource, payload) do
    Logger.info("Processing download for #{datagouv_id}")
    download_datetime = DateTime.utc_now()

    zip_metadata =
      try do
        Transport.ZipMetaDataExtractor.extract!(resource_path)
      rescue
        _ ->
          Logger.error("Cannot compute ZIP metadata for #{datagouv_id}")
          nil
      end

    computed_metadata =
      if Resource.is_gtfs?(resource) do
        case gtfs_validator().validate_from_url(Map.fetch!(payload, "href")) do
          {:ok, validation_result} ->
            Map.fetch!(validation_result, "metadata")

          {:error, message} ->
            Logger.error("GTFS validator error #{message}")
            nil
        end
      else
        nil
      end

    filename = upload_filename(resource, download_datetime)

    data = %{
      download_datetime: download_datetime,
      uuid: Ecto.UUID.generate(),
      zip_metadata: zip_metadata,
      http_headers: headers,
      resource_metadata: computed_metadata,
      title: Map.fetch!(payload["metadata"], "title"),
      filename: filename,
      permanent_url: Transport.S3.permanent_url(:history, filename),
      format: resource.format,
      filenames: zip_metadata |> Enum.map(& &1.file_name),
      total_uncompressed_size: zip_metadata |> Enum.map(& &1.uncompressed_size) |> Enum.sum(),
      total_compressed_size: zip_metadata |> Enum.map(& &1.compressed_size) |> Enum.sum(),
      from_old_system: true,
      old_href: Map.fetch!(payload, "href"),
      old_payload: payload
    }

    Transport.S3.upload_to_s3!(:history, body, filename)
    store_resource_history!(resource, data)
  end

  defp store_resource_history!(%Resource{datagouv_id: datagouv_id}, payload) do
    Logger.info("Saving ResourceHistory for #{datagouv_id}")

    %ResourceHistory{
      datagouv_id: datagouv_id,
      payload: payload,
      inserted_at: to_utc_datetime(Map.fetch!(payload.old_payload["metadata"], "updated-at"))
    }
    |> DB.Repo.insert!()
  end

  @doc """
  Converts a string datetime to utc_datetime_usec

  iex> to_utc_datetime("2020-11-17T10:28:05.852000")
  ~U[2020-11-17 10:28:05.852000Z]

  iex> to_utc_datetime("2020-11-17 10:28:05.852000")
  ~U[2020-11-17 10:28:05.852000Z]

  iex> to_utc_datetime("2020-11-17T10:28:05.852000Z")
  ~U[2020-11-17 10:28:05.852000Z]

  iex> to_utc_datetime("2020-11-17 10:28:05.852000Z")
  ~U[2020-11-17 10:28:05.852000Z]
  """
  def to_utc_datetime(date) do
    datetime = NaiveDateTime.from_iso8601!(date)
    {:ok, val} = Ecto.Type.cast(:utc_datetime_usec, datetime)
    val
  end

  def already_historised?(old_href) do
    ResourceHistory
    |> where([_], fragment("(payload ->> 'from_old_system')::boolean = true"))
    |> where([_], fragment("payload ->> 'old_href' = ?", ^old_href))
    |> Repo.exists?()
  end

  defp existing_resource(url, dataset_datagouv_id) do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([r, _d], r.url == ^url)
    |> where([_r, d], d.datagouv_id == ^dataset_datagouv_id)
    |> Repo.one()
  end

  defp download_path(%Resource{datagouv_id: datagouv_id}) do
    time = Calendar.strftime(DateTime.utc_now(), "%Y%m%d.%H%M%S.%f")
    System.tmp_dir!() |> Path.join("resource_migrate_#{datagouv_id}_#{time}_download")
  end

  defp download_resource(url, file_path) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body} = r} ->
        Logger.info("Saving #{url} to #{file_path}")
        File.write!(file_path, body)
        {:ok, file_path, relevant_http_headers(r), body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "Got a non 200 status: #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Got an error: #{reason}"}
    end
  end

  def upload_filename(%Resource{datagouv_id: datagouv_id}, %DateTime{} = dt) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{datagouv_id}/#{datagouv_id}.#{time}.zip"
  end

  defp gtfs_validator, do: Shared.Validation.GtfsValidator.Wrapper.impl()
end
