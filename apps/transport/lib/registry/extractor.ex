defmodule Transport.Registry.Extractor do
  @moduledoc """
  Interface and utilities for stops extractors.
  """

  require Logger

  alias Transport.Registry.Model.DataSource
  alias Transport.Registry.Model.Stop
  alias Transport.Registry.Result

  @callback extract_from_archive(data_source_id :: DataSource.data_source_id(), path :: Path.t()) ::
              Result.t([Stop.t()])
end
