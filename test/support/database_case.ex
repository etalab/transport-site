defmodule TransportWeb.DatabaseCase do
  @moduledoc """
  This module defines the test case to be used by
  tests interacting with database.
  """

  use ExUnit.CaseTemplate

  using(options) do
    quote do
      defp cleanup do
        collections() |> Enum.each(&(cleanup(&1)))
      end

      defp cleanup(collection) do
        Mongo.delete_many(:mongo, collection, %{}, pool: DBConnection.Poolboy)
      end

      defp collections do
        unquote(options)[:cleanup]
      end

      setup_all do
        cleanup()

        on_exit fn ->
          cleanup()
        end
      end
    end
  end
end
