defmodule Transport.ReusableDataTest do
  use ExUnit.Case, async: true
  use TransportWeb.CleanupCase, cleanup: ["datasets"]
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset

  doctest ReusableData
end
