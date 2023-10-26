defmodule Transport.Converters.Converter do
  @moduledoc """
  A behaviour for data converters, used only for GTFS files at the moment.
  """
  @callback convert(binary(), binary()) :: :ok | {:error, any()}
  @callback converter() :: binary()
  @callback converter_version() :: binary()
end
