defmodule Transport.Jobs.DatabaseBackupReplicationJob do
  @moduledoc """
  Job in charge of copying the latest database dump from one
  hosting provider's object storage to another one.

  This job checks that:
  - permissions are approriate:
    - cannot list buckets
    - cannot list objects in destination bucket
    - cannot delete and object in destination bucket
  - the latest dump has an appropriate size (between 90% and 110% compared to yesterday's dump)
  - the dump is recent enough
  - not too large
  """
  use Oban.Worker, max_attempts: 3, tags: [Transport.Jobs.ObanLogger.email_on_failure_tag()]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ensure_destination_permissions_are_appropriate!()

    check_appropriate_size!()

    latest_dump() |> check_dump_is_recent_enough!() |> upload!()

    :ok
  end

  def ensure_destination_permissions_are_appropriate! do
    # Cannot list buckets
    %{body: %{buckets: []}} = ExAws.S3.list_buckets() |> request!(:destination)
    # Cannot list objects in destination bucket
    destination_bucket = bucket_name(:destination)
    {:error, {:http_error, 403, _}} = destination_bucket |> ExAws.S3.list_objects() |> request(:destination)
    # Cannot delete an object in the destination bucket
    random_filename = Ecto.UUID.generate()

    {:error, {:http_error, 403, _}} =
      destination_bucket |> ExAws.S3.delete_object(random_filename) |> request(:destination)
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
      |> ExAws.S3.upload(bucket_name(:destination), upload_filename(dump), acl: :private, timeout: :timer.seconds(90))
      |> request!(:destination)
    after
      File.rm(tmp_path)
    end
  end

  def check_appropriate_size! do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)
    dumps = latest_source_dumps(20)
    today_size = latest_dump_for_date(dumps, today) |> dump_size()
    yesterday_size = latest_dump_for_date(dumps, yesterday) |> dump_size()

    unless 0.9 * yesterday_size <= today_size and today_size <= 1.1 * yesterday_size do
      raise "Latest backup size is unexpected. Yesterday: #{yesterday_size}, today: #{today_size}"
    end
  end

  def latest_dump_for_date(latest_dumps, %Date{} = date) do
    latest_dumps
    |> Enum.filter(fn %{last_modified: last_modified} ->
      Date.compare(last_modified |> datetime_to_date(), date) == :eq
    end)
    |> List.first()
  end

  def latest_dump, do: List.first(latest_source_dumps(1))

  def latest_source_dumps(nb_to_keep) when is_integer(nb_to_keep) and nb_to_keep > 0 do
    bucket_name = bucket_name(:source)
    %{body: %{contents: contents}} = bucket_name |> ExAws.S3.list_objects() |> request!(:source)
    contents |> Enum.sort_by(&Map.fetch!(&1, :last_modified), :desc) |> Enum.take(nb_to_keep)
  end

  def bucket_name(target), do: Map.fetch!(find_config(target), :bucket_name)

  @doc """
  Number of seconds in a given number of hours.

  iex> hours_in_seconds(3)
  10_800
  """
  def hours_in_seconds(hours), do: hours * 60 * 60

  @doc """
  Number of bytes in a given number of gigabytes.

  iex> gigabytes(2)
  2.0e9
  """
  def gigabytes(gigabytes) when is_integer(gigabytes) and gigabytes > 0 do
    gigabytes * :math.pow(1000, 3)
  end

  def check_dump_not_too_large!(dump) do
    if dump_size(dump) > max_size_threshold() do
      raise "Latest database dump is larger than 10 gigabytes #{inspect(dump)}"
    end

    dump
  end

  def dump_size(%{size: size_str}) do
    {size, ""} = Integer.parse(size_str)
    size
  end

  def check_dump_is_recent_enough!(%{last_modified: last_modified_str} = dump) do
    last_modified = NaiveDateTime.from_iso8601!(last_modified_str)

    unless NaiveDateTime.diff(NaiveDateTime.utc_now(), last_modified) < recent_enough_threshold() do
      raise "Latest database dump is not recent enough #{inspect(dump)}"
    end

    dump
  end

  def max_size_threshold, do: gigabytes(10)
  def recent_enough_threshold, do: hours_in_seconds(12)

  defp upload_filename(%{key: key}) do
    filename = key |> String.replace_trailing(".dump", "")
    [filename, Ecto.UUID.generate(), "dump"] |> Enum.join(".")
  end

  defp request(operation, target) when target in [:source, :destination] do
    operation |> Transport.Wrapper.ExAWS.impl().request(find_config(target))
  end

  defp request!(operation, target) when target in [:source, :destination] do
    operation |> Transport.Wrapper.ExAWS.impl().request!(find_config(target))
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

  defp datetime_to_date(dt_string) when is_binary(dt_string) do
    {:ok, dt, 0} = "#{String.trim_trailing(dt_string, "Z")}Z" |> DateTime.from_iso8601()
    DateTime.to_date(dt)
  end
end
