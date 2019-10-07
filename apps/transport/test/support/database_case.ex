defmodule TransportWeb.DatabaseCase do
  @moduledoc """
  This module defines the test case to be used by
  tests interacting with database.
  """

  use ExUnit.CaseTemplate

  using(options) do
    quote do
      alias Ecto.Adapters.SQL.Sandbox
      alias DB.{AOM, Dataset, Region, Repo}

      import Ecto
      import Ecto.Query

      defp cleanup do
        collections() |> Enum.each(&(cleanup(&1)))
      end

      defp cleanup(:datasets), do: Repo.delete_all(Dataset)

      defp collections do
        unquote(options)[:cleanup]
      end

      setup context do
        :ok = Sandbox.checkout(Repo)
        unless context[:async] do
          Sandbox.mode(Transport.Repo, {:shared, self()})
        end

        Repo.insert(%Region{nom: "Pays de la Loire"})
        Repo.insert(%Region{nom: "Auvergne-Rhône-Alpes"})
        Repo.insert(%AOM{
          insee_commune_principale: "53130",
          nom: "Laval",
          region: Repo.get_by(Region, nom: "Pays de la Loire")}
        )
        Repo.insert(%AOM{
          insee_commune_principale: "38185",
          nom: "Grenoble",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes")}
        )

        cleanup()
        on_exit fn ->
          :ok = Sandbox.checkout(Repo)
          cleanup()
        end
        :ok
      end
    end
  end
end
