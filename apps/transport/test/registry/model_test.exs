defmodule Transport.Registry.ModelTest do
  use ExUnit.Case, async: true
  doctest Transport.Registry.Model.DataSource, import: true
  doctest Transport.Registry.Model.Stop, import: true
  doctest Transport.Registry.Model.StopIdentifier, import: true
end
