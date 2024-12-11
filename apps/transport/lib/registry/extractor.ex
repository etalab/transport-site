defmodule Transport.Registry.Extractor do
  alias Transport.Registry.Model.Stop

  @type result(positive) :: {:ok, positive} | {:error, binary()}

  @callback extract_from_archive(path :: Path.t()) :: result([Stop.t()])
end
