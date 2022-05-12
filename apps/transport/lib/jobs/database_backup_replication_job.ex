defmodule Transport.Jobs.DatabaseBackupReplicationJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTEntitiesJob`.
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ensure_destination_credentials_cannot_read!()

    latest_dump()
    |> check_dump_not_too_large!()
    |> check_dump_is_recent_enough!()
    |> upload!()

    :ok
  end

  def ensure_destination_credentials_cannot_read! do
    # Cannot list buckets
    %{body: %{buckets: []}} = ExAws.S3.list_buckets() |> request!(:destination)
    # Cannot list objects in destination bucket
    {:error, {:http_error, 403, _}} = :destination |> bucket_name() |> ExAws.S3.list_objects() |> request(:destination)
  end

  def upload!(dump) do
    tmp_path = System.tmp_dir!() |> Path.join(Ecto.UUID.generate())

    try do
      :source
      |> bucket_name()
      |> ExAws.S3.download_file(Map.fetch!(dump, :key), tmp_path)
      |> request!(:source)

      tmp_path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket_name(:destination), upload_filename(dump))
      |> request!(:destination)
    after
      File.rm(tmp_path)
    end
  end

  def latest_dump, do: List.first(latest_source_dumps(1))

  def latest_source_dumps(nb_to_keep) when is_integer(nb_to_keep) and nb_to_keep > 0 do
    bucket_name = bucket_name(:source)
    %{body: %{contents: contents}} = bucket_name |> ExAws.S3.list_objects() |> request!(:source)
    contents |> Enum.sort_by(&Map.fetch!(&1, :last_modified), :desc) |> Enum.take(nb_to_keep)
  end

  def request(operation, target) when target in [:source, :destination] do
    operation |> Transport.Wrapper.ExAWS.impl().request(find_config(target))
  end

  def request!(operation, target) when target in [:source, :destination] do
    operation |> Transport.Wrapper.ExAWS.impl().request!(find_config(target))
  end

  def bucket_name(target), do: Map.fetch!(find_config(target), :bucket_name)

  def hours_in_seconds(hours), do: hours * 60 * 60

  @doc """
  Number of bytes in a given number of gigabytes.

  iex> gigabytes(2)
  2.0e9
  """
  def gigabytes(gigabytes) when is_integer(gigabytes) and gigabytes > 0 do
    gigabytes * 1.0e9
  end

  defp find_config(target) when target in [:source, :destination] do
    Map.fetch!(
      %{
        source: ExAws.Config.new(:s3, Application.fetch_env!(:ex_aws, :database_backup_source)),
        destination: ExAws.Config.new(:s3, Application.fetch_env!(:ex_aws, :database_backup_destination))
      },
      target
    )
  end

  defp check_dump_not_too_large!(%{size: size_str} = dump) do
    {size, ""} = Integer.parse(size_str)

    if size > gigabytes(1) do
      raise "Latest database dump is larger than 1 gigabytes #{inspect(dump)}"
    end

    dump
  end

  defp check_dump_is_recent_enough!(%{last_modified: last_modified_str} = dump) do
    last_modified = NaiveDateTime.from_iso8601!(last_modified_str)

    unless NaiveDateTime.diff(NaiveDateTime.utc_now(), last_modified) < hours_in_seconds(12) do
      raise "Latest database dump is not recent enough #{inspect(dump)}"
    end

    dump
  end

  defp upload_filename(%{key: key}) do
    filename = key |> String.replace_trailing(".dump", "")
    [filename, Ecto.UUID.generate(), "dump"] |> Enum.join(".")
  end
end
