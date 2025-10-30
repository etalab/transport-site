defmodule TransportWeb.DatabaseCase do
  @moduledoc """
  This module defines the test case to be used by
  tests interacting with database.
  """

  use ExUnit.CaseTemplate

  using(options) do
    quote do
      alias DB.{AOM, Commune, Dataset, Region, Repo}
      alias Ecto.Adapters.SQL.Sandbox

      import Ecto
      import Ecto.Query

      defp cleanup do
        collections() |> Enum.each(&cleanup(&1))
      end

      defp cleanup(:datasets), do: Repo.delete_all(Dataset)

      defp collections do
        unquote(options)[:cleanup]
      end

      setup context do
        :ok = Sandbox.checkout(Repo)

        unless context[:async] do
          Sandbox.mode(Repo, {:shared, self()})
        end

        Repo.insert(%Region{nom: "Pays de la Loire", insee: "52"})
        Repo.insert(%Region{nom: "Auvergne-Rhône-Alpes", insee: "84"})
        Repo.insert(%Region{nom: "Île-de-France", insee: "11"})

        Repo.insert(%AOM{
          insee_commune_principale: "53130",
          nom: "Laval",
          region: Repo.get_by(Region, nom: "Pays de la Loire"),
          population: 42
        })

        Repo.insert(%AOM{
          insee_commune_principale: "38185",
          nom: "Grenoble",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes"),
          population: 43
        })

        Repo.insert(%AOM{
          insee_commune_principale: "36044",
          nom: "Châteauroux",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes"),
          population: 44
        })

        Repo.insert(%Commune{
          insee: "38185",
          nom: "Grenoble",
          surf_ha: 200_554.0
        })

        Repo.insert(%Commune{
          insee: "36044",
          nom: "Châteauroux",
          surf_ha: 2554.0
        })

        Repo.insert(%Commune{
          insee: "63096",
          nom: "Chas",
          surf_ha: 254.0
        })

        Repo.insert(%AOM{
          insee_commune_principale: "75056",
          nom: "Île-de-France Mobilités",
          region: Repo.get_by(Region, nom: "Île-de-France"),
          population: 45
        })

        Repo.insert(%Commune{
          insee: "36063",
          nom: "Déols",
          surf_ha: 3177.0
        })

        cleanup()

        on_exit(fn ->
          :ok = Sandbox.checkout(Repo)
          cleanup()
        end)

        :ok
      end
    end
  end
end
