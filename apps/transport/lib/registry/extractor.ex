defmodule Transport.Registry.Extractor do
  @moduledoc """
  Interface and utilities for stops extractors.
  """

  require Logger

  alias Transport.Registry.Model.Stop
  alias Transport.Registry.Result

  @callback extract_from_archive(path :: Path.t()) :: Result.t([Stop.t()])
end
