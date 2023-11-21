defmodule Transport.Jobs.GTFSToNeTExConverterJob do
  @moduledoc """
  This will enqueue GTFS -> NeTEx conversion jobs for all GTFS resources found in ResourceHistory
  """
  use Oban.Worker, tags: ["conversions"], max_attempts: 3
  alias Transport.Jobs.GTFSGenericConverter

  @impl true
  def perform(%{}) do
    GTFSGenericConverter.enqueue_all_conversion_jobs("NeTEx", [
      Transport.Jobs.SingleGTFSToNeTExHoveConverterJob,
      Transport.Jobs.GTFSToNeTExEnRouteConverterJob
    ])
  end
end

defmodule Transport.Jobs.SingleGTFSToNeTExHoveConverterJob do
  @moduledoc """
  Conversion job of a GTFS to a NeTEx using the Hover converter, saving the resulting file in S3
  """
  use Oban.Worker, tags: ["conversions"], max_attempts: 3, queue: :heavy, unique: [period: :infinity]
  alias Transport.Jobs.GTFSGenericConverter

  defdelegate converter(), to: Transport.GTFSToNeTExHoveConverter

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    GTFSGenericConverter.perform_single_conversion_job(resource_history_id, "NeTEx", Transport.GTFSToNeTExHoveConverter)
  end

  @impl true
  def backoff(%Oban.Job{attempt: attempt}) do
    # Retry in 1 day, in 2 days, in 3 days etc.
    one_day = 60 * 60 * 24
    attempt * one_day
  end
end

defmodule Transport.Jobs.DatasetGTFSToNeTExConverterJob do
  @moduledoc """
  This will enqueue GTFS -> NeTEx conversions jobs for all GTFS resources linked to a dataset, but only for the most recent resource history
  """
  use Oban.Worker, tags: ["conversions"], max_attempts: 3, queue: :heavy
  import Ecto.Query

  @impl true
  def perform(%{args: %{"dataset_id" => dataset_id}}) do
    dataset_id
    |> list_gtfs_last_resource_history()
    |> Enum.each(&enqueue_conversion_jobs/1)
  end

  defp enqueue_conversion_jobs(resource_history_id) do
    [
      Transport.Jobs.SingleGTFSToNeTExHoveConverterJob,
      Transport.Jobs.GTFSToNeTExEnRouteConverterJob
    ]
    |> Enum.each(fn converter ->
      %{"resource_history_id" => resource_history_id, "action" => "create"}
      |> converter.new()
      |> Oban.insert()
    end)
  end

  @spec list_gtfs_last_resource_history(binary()) :: list()
  def list_gtfs_last_resource_history(dataset_id) do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> where([dataset: d, resource: r], d.id == ^dataset_id and r.format == "GTFS")
    |> select([resource_history: rh], rh.id)
    |> DB.Repo.all()
  end
end

defmodule Transport.GTFSToNeTExHoveConverter do
  @moduledoc """
  Given a GTFS file path, convert it to NeTEx.
  """
  @behaviour Transport.Converters.Converter

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

  @impl true
  def converter, do: "hove/transit_model"

  @impl true
  def converter_version, do: "0.55.0"
end
