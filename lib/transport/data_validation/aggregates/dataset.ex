defmodule Transport.DataValidation.Aggregates.Dataset do
  @moduledoc """
  A dataset is a container for dataset validations.
  """

  defstruct [:uuid, :download_url, :validations]

  use GenServer
  use ExConstructor
  alias Transport.DataValidation.Supervisor
  alias Transport.DataValidation.Aggregates.Dataset
  alias Transport.DataValidation.Queries.FindDataset
  alias Transport.DataValidation.Commands.{CreateDataset, ValidateDataset}
  alias Transport.DataValidation.Repo.Dataset, as: Repo

  @registry :dataset_registry
  @timeout 50_000

  @type t :: %__MODULE__{
          uuid: String.t(),
          download_url: String.t(),
          validations: [Dataset.Validation.t()]
        }

  def start_link(download_url) when is_binary(download_url) do
    GenServer.start_link(
      __MODULE__,
      %__MODULE__{download_url: download_url},
      name: via_tuple(download_url)
    )
  end

  def init(%__MODULE__{} = dataset) do
    {:ok, dataset}
  end

  def execute(%FindDataset{} = query) do
    query.download_url
    |> registry_lookup
    |> GenServer.call({:find_dataset, query}, @timeout)
  end

  def execute(%CreateDataset{} = command) do
    command.download_url
    |> registry_lookup
    |> GenServer.call({:create_dataset, command}, @timeout)
  end

  def execute(%ValidateDataset{} = command) do
    command.download_url
    |> registry_lookup
    |> GenServer.call({:validate_dataset, command}, @timeout)
  end

  def handle_call(
        {:find_dataset, %FindDataset{} = query},
        _from,
        %__MODULE__{uuid: nil} = dataset
      ) do
    case Repo.execute(query) do
      {:ok, dataset} -> {:reply, {:ok, dataset}, dataset}
      {:error, error} -> {:reply, {:error, error}, dataset}
    end
  end

  def handle_call({:find_dataset, %FindDataset{}}, _from, %__MODULE__{} = dataset) do
    {:reply, {:ok, dataset}, dataset}
  end

  def handle_call(
        {:create_dataset, %CreateDataset{} = command},
        _from,
        %__MODULE__{uuid: nil} = dataset
      ) do
    case Repo.execute(command) do
      {:ok, dataset} -> {:reply, {:ok, dataset}, dataset}
      {:error, error} -> {:reply, {:error, error}, dataset}
    end
  end

  def handle_call({:create_dataset, %CreateDataset{}}, _from, %__MODULE__{} = dataset) do
    {:reply, {:ok, dataset}, dataset}
  end

  def handle_call(
        {:validate_dataset, %ValidateDataset{} = command},
        _from,
        %__MODULE__{} = dataset
      ) do
    case Repo.execute(command) do
      {:ok, validations} ->
        {:reply, {:ok, validations}, %Dataset{dataset | validations: validations}}

      {:error, error} ->
        {:reply, {:error, error}, dataset}
    end
  end

  # private

  defp via_tuple(download_url) when is_binary(download_url) do
    {:via, Registry, {@registry, download_url}}
  end

  defp registry_lookup(download_url) when is_binary(download_url) do
    case Registry.lookup(@registry, download_url) do
      [{pid, _}] ->
        pid

      [] ->
        {:ok, pid} = Supervisor.start_dataset(download_url)
        pid
    end
  end
end
