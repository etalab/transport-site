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

defmodule Transport.Jobs.DatasetGtfsToNetexConverterJob do
  @moduledoc """
  This will enqueue GTFS -> NeTEx conversions jobs for all GTFS resources linked to a dataset, but only for the most recent resource history
  """
  use Oban.Worker, max_attempts: 3, queue: :heavy
  alias Transport.Jobs.GTFSGenericConverter
  import Ecto.Query

  def list_GTFS_last_resource_history(dataset_id) do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> where([dataset: d, resource: r], d.id == ^dataset_id and r.format == "GTFS")
    |> select([resource_history: rh], rh.id)
    |> DB.Repo.all()
  end

  @impl true
  def perform(%{args: %{"dataset_id" => dataset_id}}) do
    dataset_id
    |> list_GTFS_last_resource_history()
    |> Enum.each(fn rh_id ->
      GTFSGenericConverter.perform_single_conversion_job(rh_id, "NeTEx", Transport.GtfsToNeTExConverter)
    end)
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
