defmodule Transport.Jobs.ResourceHistoryAndValidationDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceHistoryJob`
  """
  use Oban.Worker, unique: [period: {5, :hours}], tags: ["history"], max_attempts: 5
  require Logger
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mode" => "reuser_improved_data"}}) do
    DB.ReuserImprovedData.base_query()
    |> select([reuser_improved_data: rid], rid.id)
    |> DB.Repo.all()
    |> Enum.map(fn reuser_improved_data_id ->
      %{reuser_improved_data_id: reuser_improved_data_id}
      |> Transport.Jobs.ResourceHistoryJob.historize_and_validate_job()
    end)
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(_job) do
    resource_ids = Enum.map(resources_to_historise(), & &1.id)

    Logger.debug("Dispatching #{Enum.count(resource_ids)} ResourceHistoryJob jobs")

    resource_ids
    |> Enum.map(fn resource_id ->
      %{resource_id: resource_id} |> Transport.Jobs.ResourceHistoryJob.historize_and_validate_job()
    end)
    |> Oban.insert_all()

    :ok
  end

  def resources_to_historise(resource_id \\ nil) do
    dataset_ids = DB.Dataset.base_with_hidden_datasets() |> select([dataset: d], d.id)

    base_query =
      DB.Resource.base_query()
      |> where([resource: r], not is_nil(r.url) and not is_nil(r.title))
      |> where([resource: r], not r.is_community_resource)
      |> where([resource: r], like(r.url, "http%"))
      |> where([resource: r], r.dataset_id in subquery(dataset_ids))
      |> preload(:dataset)

    query = if is_nil(resource_id), do: base_query, else: where(base_query, [resource: r], r.id == ^resource_id)

    query
    |> DB.Repo.all()
    |> Enum.reject(
      &(DB.Resource.real_time?(&1) or DB.Resource.documentation?(&1) or DB.Dataset.should_skip_history?(&1.dataset))
    )
  end
end

defmodule Transport.Jobs.ResourceHistoryJob do
  @moduledoc """
  Job historicising a single `DB.Resource` or a `DB.ReuserImprovedData`.
  """
  use Oban.Worker, unique: [period: {5, :hours}, fields: [:args, :queue, :worker]], tags: ["history"], max_attempts: 5
  require Logger
  import Ecto.Query
  alias Transport.Schemas.Wrapper, as: Schemas
  import Transport.Jobs.Workflow.Notifier, only: [notify_workflow: 2]

  @headers_to_keep [
    "content-disposition",
    "content-encoding",
    "content-length",
    "content-type",
    "etag",
    "expires",
    "if-modified-since",
    "last-modified"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}} = job) do
    Logger.info("Running ResourceHistoryJob for resource##{resource_id}")

    resource_id
    |> Transport.Jobs.ResourceHistoryAndValidationDispatcherJob.resources_to_historise()
    |> handle_history(job)
  end

  def perform(%Oban.Job{args: %{"reuser_improved_data_id" => reuser_improved_data_id}} = job) do
    DB.Repo.get!(DB.ReuserImprovedData, reuser_improved_data_id)
    |> handle_history(job)
  end

  defp handle_history([], %Oban.Job{} = job) do
    reason = "Resource should not be historicised"
    notify_workflow(job, %{"success" => false, "job_id" => job.id, "reason" => reason})
    {:cancel, reason}
  end

  defp handle_history([%DB.Resource{} = resource], %Oban.Job{} = job) do
    do_handle_history(resource, job)
  end

  defp handle_history(%DB.ReuserImprovedData{} = reuser_improved_data, %Oban.Job{} = job) do
    do_handle_history(reuser_improved_data, job)
  end

  defp do_handle_history(data, %Oban.Job{} = job) do
    path = download_path(data)

    notification =
      try do
        %{resource_history_id: resource_history_id} =
          download_resource(data, path) |> process_download(data)

        %{"success" => true, "job_id" => job.id, "output" => %{resource_history_id: resource_history_id}}
      rescue
        e ->
          %{"success" => false, "job_id" => job.id, "reason" => inspect(e)}
      after
        remove_file(path)
      end

    notify_workflow(job, notification)
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(2)

  defp process_download({:error, message}, %DB.Resource{id: resource_id}) do
    # Good opportunity to add a :telemetry event
    # Consider storing in our database that the resource
    # was not available.
    Logger.debug("Got an error while downloading resource##{resource_id}: #{message}")
  end

  defp process_download({:ok, resource_path, headers}, resource_or_improved_data) do
    download_datetime = DateTime.utc_now()

    hash = resource_hash(resource_or_improved_data, resource_path)

    case should_store_resource?(resource_or_improved_data, hash) do
      true ->
        filename = upload_filename(resource_or_improved_data, resource_path, download_datetime)

        base = %{
          download_datetime: download_datetime,
          uuid: Ecto.UUID.generate(),
          http_headers: headers,
          filename: filename,
          permanent_url: Transport.S3.permanent_url(:history, filename)
        }

        data =
          if Transport.ZipMetaDataExtractor.zip?(resource_path) do
            total_compressed_size = hash |> Enum.map(& &1.compressed_size) |> Enum.sum()

            Map.merge(base, %{
              zip_metadata: hash,
              filenames: hash |> Enum.map(& &1.file_name),
              total_uncompressed_size: hash |> Enum.map(& &1.uncompressed_size) |> Enum.sum(),
              total_compressed_size: total_compressed_size,
              filesize: total_compressed_size
            })
          else
            %{size: size} = File.stat!(resource_path)
            Map.merge(base, %{content_hash: hash, filesize: size})
          end

        Transport.S3.stream_to_s3!(:history, resource_path, filename, acl: :public_read)
        %{id: resource_history_id} = store_resource_history!(resource_or_improved_data, data)
        Appsignal.increment_counter("resource_history_job.success", 1)
        %{resource_history_id: resource_history_id}

      {false, history} ->
        Appsignal.increment_counter("resource_history_job.skipped", 1)
        touch_resource_history!(history)
        %{resource_history_id: history.id}

      false ->
        Appsignal.increment_counter("resource_history_job.failed", 1)
        Logger.error("Historization failed for #{inspect(resource_or_improved_data)}")
        {:error, "historization failed"}
    end
  end

  @doc """
  Determine if we would historicise a payload now.

  We should historicise a resource if:
  - we never historicised it
  - the latest ResourceHistory payload is different than the current state
  """
  def should_store_resource?(_, []), do: false
  def should_store_resource?(_, nil), do: false

  def should_store_resource?(%DB.Resource{id: resource_id}, resource_hash) do
    DB.ResourceHistory
    |> where([r], r.resource_id == ^resource_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> DB.Repo.one()
    |> compare_history(resource_hash)
  end

  def should_store_resource?(%DB.ReuserImprovedData{id: reuser_improved_data_id}, resource_hash) do
    DB.ResourceHistory
    |> where([r], r.reuser_improved_data_id == ^reuser_improved_data_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> DB.Repo.one()
    |> compare_history(resource_hash)
  end

  defp compare_history(history, resource_hash) do
    case {history, same_resource?(history, resource_hash)} do
      {nil, _} -> true
      {_history, false} -> true
      {history, true} -> {false, history}
    end
  end

  @doc """
  Determines if a ZIP metadata payload is the same that was stored in
  the latest resource_history's row in the database by comparing sha256
  hashes for all files in the ZIP.
  """
  def same_resource?(%DB.ResourceHistory{payload: %{"zip_metadata" => rh_zip_metadata}}, zip_metadata) do
    MapSet.equal?(set_of_sha256(rh_zip_metadata), set_of_sha256(zip_metadata))
  end

  def same_resource?(%DB.ResourceHistory{payload: %{"content_hash" => rh_content_hash}}, content_hash) do
    rh_content_hash == content_hash
  end

  def same_resource?(nil, _), do: false

  def set_of_sha256(items) do
    items |> Enum.map(&{map_get(&1, :file_name), map_get(&1, :sha256)}) |> MapSet.new()
  end

  defp resource_hash(data, resource_path) do
    if Transport.ZipMetaDataExtractor.zip?(resource_path) do
      try do
        Transport.ZipMetaDataExtractor.extract!(resource_path)
      rescue
        _ ->
          case data do
            %DB.Resource{} = resource ->
              Logger.error("Cannot compute ZIP metadata for resource##{resource.id}")

            _ ->
              :ok
          end

          nil
      end
    else
      Hasher.get_file_hash(resource_path)
    end
  end

  def map_get(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp store_resource_history!(%DB.Resource{} = resource, payload) do
    %DB.ResourceHistory{
      datagouv_id: resource.datagouv_id,
      resource_id: resource.id,
      payload:
        Map.merge(payload, %{
          resource_url: resource.url,
          resource_latest_url: resource.latest_url,
          title: resource.title,
          format: resource.format,
          dataset_id: resource.dataset_id,
          schema_name: resource.schema_name,
          schema_version: resource.schema_version,
          latest_schema_version_to_date: latest_schema_version_to_date(resource)
        }),
      last_up_to_date_at: DateTime.utc_now()
    }
    |> DB.Repo.insert!()
  end

  defp store_resource_history!(%DB.ReuserImprovedData{id: reuser_improved_data_id}, payload) do
    %DB.ResourceHistory{
      reuser_improved_data_id: reuser_improved_data_id,
      payload: Map.merge(payload, %{format: "GTFS"}),
      last_up_to_date_at: DateTime.utc_now()
    }
    |> DB.Repo.insert!()
  end

  defp touch_resource_history!(%DB.ResourceHistory{id: id, resource_id: resource_id} = history) do
    Logger.debug("Touching unchanged ResourceHistory #{id} for resource##{resource_id}")

    history |> Ecto.Changeset.change(%{last_up_to_date_at: DateTime.utc_now()}) |> DB.Repo.update!()
  end

  defp download_path(%DB.Resource{id: resource_id}) do
    System.tmp_dir!() |> Path.join("resource_#{resource_id}_download")
  end

  defp download_path(%DB.ReuserImprovedData{id: reuser_improved_data_id}) do
    System.tmp_dir!() |> Path.join("reuser_improved_data_#{reuser_improved_data_id}_download")
  end

  def download_resource(%DB.Resource{url: url}, file_path) do
    download_resource(url, file_path)
  end

  def download_resource(%DB.ReuserImprovedData{download_url: download_url}, file_path) do
    download_resource(download_url, file_path)
  end

  def download_resource(url, file_path) when is_binary(url) do
    file_stream = File.stream!(file_path)
    req_options = [compressed: false, decode_body: false, receive_timeout: 180_000, into: file_stream]

    case Transport.Req.impl().get(url, req_options) do
      {:ok, %{status: 200} = r} ->
        {:ok, file_path, relevant_http_headers(r)}

      {:ok, %{status: status_code}} ->
        # NOTE: the file is still on disk at this point
        {:error, "Got a non 200 status: #{status_code}"}

      {:error, error} ->
        {:error, "Got an error: #{error |> inspect}"}
    end
  end

  def http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  def remove_file(path), do: File.rm(path)

  def upload_filename(%DB.Resource{id: resource_id} = resource, resource_path, %DateTime{} = dt) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "#{resource_id}/#{resource_id}.#{time}#{file_extension(resource, resource_path)}"
  end

  def upload_filename(
        %DB.ReuserImprovedData{id: reuser_improved_data_id} = reuser_improved_data,
        resource_path,
        %DateTime{} = dt
      ) do
    time = Calendar.strftime(dt, "%Y%m%d.%H%M%S.%f")

    "reuser_improved_data_#{reuser_improved_data_id}/#{reuser_improved_data_id}.#{time}#{file_extension(reuser_improved_data, resource_path)}"
  end

  @doc """
  Guess an appropriate file extension according to a format.
  """
  def file_extension(%DB.Resource{format: format}, resource_path) do
    if Transport.ZipMetaDataExtractor.zip?(resource_path) do
      ".zip"
    else
      "." <> (format |> String.downcase() |> String.replace_prefix(".", ""))
    end
  end

  def file_extension(%DB.ReuserImprovedData{}, resource_path) do
    if Transport.ZipMetaDataExtractor.zip?(resource_path) do
      ".zip"
    else
      raise "not implemented"
    end
  end

  def relevant_http_headers(%HTTPoison.Response{headers: headers}) do
    headers |> Enum.into(%{}, fn {h, v} -> {String.downcase(h), v} end) |> Map.take(@headers_to_keep)
  end

  @doc """
    Extract only the HTTP headers we need. Concatenate them if multiple values are found (rare but can occur if we
    allow more headers).

    iex> relevant_http_headers(%Req.Response{headers: %{"foo" => ["bar"]}})
    %{}
    iex> relevant_http_headers(%Req.Response{headers: %{"content-type" => ["application/json"]}})
    %{"content-type" => "application/json"}
    iex> relevant_http_headers(%Req.Response{headers: %{"content-type" => ["application/json", "but-also/csv"]}})
    %{"content-type" => "application/json, but-also/csv"}

    Resist to ill-formed attachments (https://github.com/etalab/transport-site/issues/3984)

    Supports latin1 (ISO-8859-1) headers
    iex> relevant_http_headers(%Req.Response{headers: %{"content-disposition" => ["attachment; filename=\\"" <> <<233, 233, 232>> <> ".zip\\""]}})
    %{"content-disposition" => "attachment; filename=\\"ééè.zip\\""}

    Still support UTF-8 header (http2)
    iex> relevant_http_headers(%Req.Response{headers: %{"content-disposition" => ["attachment; filename=\\"éè.zip\\""]}})
    %{"content-disposition" => "attachment; filename=\\"éè.zip\\""}
    iex> relevant_http_headers(%Req.Response{headers: %{"content-disposition" => [~S(attachment; filename="éè.zip")]}})
    %{"content-disposition" => "attachment; filename=\\"éè.zip\\""}
  """
  def relevant_http_headers(%Req.Response{headers: headers}) do
    headers
    |> Map.take(@headers_to_keep)
    |> Enum.into(%{}, fn {h, v} -> {String.downcase(h), v |> Enum.map_join(", ", &cleanup_header(h, &1))} end)
  end

  defp cleanup_header("content-disposition", binary) do
    if String.valid?(binary) do
      # UTF-8 binary, nothing to do
      binary
    else
      # Latin1 binary (old specification), let's transcode
      :erlang.binary_to_list(binary) |> :unicode.characters_to_binary(:latin1, :utf8)
    end
  end

  defp cleanup_header(_header, binary), do: binary

  defp latest_schema_version_to_date(%DB.Resource{schema_name: nil}), do: nil

  defp latest_schema_version_to_date(%DB.Resource{schema_name: schema_name}) do
    Schemas.latest_version(schema_name)
  end

  @spec historize_and_validate_job(%{resource_id: integer()} | %{reuser_improved_data_id: integer()}, keyword()) ::
          Oban.Job.changeset()
  def historize_and_validate_job(first_jobs_args, options \\ []) do
    history_options = options |> Keyword.get(:history_options, []) |> Transport.Jobs.Workflow.kw_to_map()
    validation_custom_args = options |> Keyword.get(:validation_custom_args, %{})

    # jobs is a list of jobs that will be enqueued as a workflow.
    # if ResourceHistoryJob is a success, ResourceHistoryValidationJob will be enqueued.
    jobs = [
      [Transport.Jobs.ResourceHistoryJob, %{}, history_options],
      [Transport.Jobs.ResourceHistoryValidationJob, validation_custom_args, %{}]
    ]

    Transport.Jobs.Workflow.new(%{jobs: jobs, first_job_args: first_jobs_args})
  end
end
