defmodule TransportWeb.DatabaseCase do
  @moduledoc """
  This module defines the test case to be used by
  tests interacting with database.
  """

  use ExUnit.CaseTemplate

  using(options) do
    quote do
      alias Transport.{AOM, Dataset, Region, Repo}

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
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        unless context[:async] do
          Ecto.Adapters.SQL.Sandbox.mode(Transport.Repo, {:shared, self()})
        end

        Repo.insert(%Region{nom: "Pays de la Loire"})
        Repo.insert(%AOM{
          insee_commune_principale: "53130",
          nom: "Laval",
          region: Repo.get_by(Region, nom: "Pays de la Loire")}
        )
        Repo.insert(%AOM{
          insee_commune_principale: "85191",
          nom: "La Roche sur Yon",
          region: Repo.get_by(Region, nom: "Pays de la Loire")}
        )

        cleanup()
        on_exit fn ->
          :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
          cleanup()
        end
        :ok
      end
    end
  end
end
