defmodule DB.ResourceTest do
  use ExUnit.Case, async: true
  alias DB.{Resource, Validation}
  import Mox

  doctest Resource

  setup :verify_on_exit!

  test "validate and save a resource"
end
