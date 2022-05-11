defmodule Transport.Jobs.GtfsToNetexConverterJob do
  @moduledoc """
  This will enqueue GTFS -> NeTEx conversion jobs for all GTFS resources found in ResourceHistory
  """
  use Oban.Worker, max_attempts: 3
  alias Transport.Jobs.GTFSGenericConverter

  @impl true
  def perform(%{}) do
    GTFSGenericConverter.enqueue_all_conversion_jobs("NeTEx", Transport.Jobs.SingleGtfsToNetexConverterJob)
  end
end

defmodule Transport.Jobs.SingleGtfsToNetexConverterJob do
  @moduledoc """
  Conversion Job of a GTFS to a NeTEx, saving the resulting file in S3
  """
  use Oban.Worker, max_attempts: 3, queue: :heavy, unique: [period: :infinity]
  alias Transport.Jobs.GTFSGenericConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    GTFSGenericConverter.perform_single_conversion_job(resource_history_id, "NeTEx", Transport.GtfsToNeTExConverter)
  end

  @impl true
  def backoff(%Oban.Job{attempt: attempt}) do
    # Retry in 1 day, in 2 days, in 3 days etc.
    one_day = 60 * 60 * 24
    attempt * one_day
  end
end

defmodule Transport.GtfsToNeTExConverter do
  @moduledoc """
  Given a GTFS file path, convert it to NeTEx.
  """
  @spec convert(binary(), binary()) :: :ok | {:error, any()}
  def convert(gtfs_file_path, netex_file_path) do
    binary_path = Path.join(Application.fetch_env!(:transport, :transport_tools_folder), "gtfs2netexfr")
    participant = Application.get_env(:transport, :domain_name)

    case Transport.RamboLauncher.run(
           binary_path,
           ["--input", gtfs_file_path, "--output", netex_file_path, "--participant", participant]
         ) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, e}
    end
  end
end
