defmodule Transport.ValidatorsSelection do
  @callback formats_and_validators() :: map()

  def impl(), do: Application.get_env(:transport, :validator_selection)
  def formats_and_validators, do: impl().formats_and_validators()

  def validators(format, formats_and_validators \\ formats_and_validators()),
    do: impl().validators(format, formats_and_validators)
end

defmodule Transport.ValidatorsSelection.Impl do
  @moduledoc """
  Lists wich validators should run for each resource format (GBFS, GTFS, NeTEx, etc)
  Give tools to fetch the validators list for a format
  """
  @behaviour Transport.ValidatorsSelection
  alias Transport.Validators

  @impl Transport.ValidatorsSelection
  @spec formats_and_validators :: map()
  def formats_and_validators do
    %{"GTFS" => [Validators.GTFSTransport]}
  end

  @doc """
  get a list of validators to run for a given format

  iex> validators("GBFS", %{"GBFS" => ["v1", "v2"], "GTFS" => ["v3"]})
  ["v1", "v2"]
  iex> validators("GBFS", %{"GTFS" => ["v1"]})
  []
  """
  @spec validators(binary()) :: list()
  def validators(format, formats_and_validators \\ formats_and_validators()) do
    formats_and_validators
    |> Map.get(format, [])
  end
end
