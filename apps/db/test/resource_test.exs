defmodule DB.ResourceTest do
  use ExUnit.Case, async: true
  alias DB.{Resource, Validation}
  import Mox

  doctest Resource

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "validate and save a resource"
end
