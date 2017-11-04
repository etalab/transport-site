defmodule TransportWeb.FactoryCase do
  use ExUnit.CaseTemplate

  using(options) do
    quote do
      def insert(factory, collection) do
        Mongo.insert_one(:mongo, collection, factory, pool: DBConnection.Poolboy)
      end

      defp cleanup(:all) do
        collections() |> Enum.each(&(cleanup(&1)))
      end

      defp cleanup(collection) do
        Mongo.delete_many(:mongo, collection, %{}, pool: DBConnection.Poolboy)
      end

      defp collections do
        unquote(options)[:collections]
      end

      setup_all do
        cleanup(:all)

        on_exit fn ->
          cleanup(:all)
        end
      end
    end
  end
end
