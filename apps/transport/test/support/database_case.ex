defmodule TransportWeb.DatabaseCase do
  @moduledoc """
  This module defines the test case to be used by
  tests interacting with database.
  """

  use ExUnit.CaseTemplate

  using(options) do
    quote do
      alias Ecto.Adapters.SQL.Sandbox
      alias DB.{AOM, Commune, Dataset, Region, Repo}

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

        Repo.insert(%Region{nom: "Pays de la Loire"})
        Repo.insert(%Region{nom: "Auvergne-Rhône-Alpes"})
        Repo.insert(%Region{nom: "Île-de-France"})

        Repo.insert(%AOM{
          insee_commune_principale: "53130",
          nom: "Laval",
          region: Repo.get_by(Region, nom: "Pays de la Loire"),
          composition_res_id: 1
        })

        Repo.insert(%AOM{
          insee_commune_principale: "38185",
          nom: "Grenoble",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes"),
          composition_res_id: 2
        })

        Repo.insert(%AOM{
          insee_commune_principale: "36044",
          nom: "Châteauroux",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes"),
          composition_res_id: 3
        })

        Repo.insert(%Commune{
          insee: "38185",
          nom: "Grenoble",
          surf_ha: 200_554.0,
          aom_res_id: 2
        })

        Repo.insert(%Commune{
          insee: "36044",
          nom: "Châteauroux",
          surf_ha: 2554.0,
          aom_res_id: 3
        })

        Repo.insert(%Commune{
          insee: "63096",
          nom: "Chas",
          surf_ha: 254.0,
          aom_res_id: 3
        })

        Repo.insert(%AOM{
          insee_commune_principale: "75056",
          nom: "Île-de-France Mobilités",
          region: Repo.get_by(Region, nom: "Île-de-France"),
          composition_res_id: 4
        })

        Repo.insert(%Commune{
          insee: "36063",
          nom: "Déols",
          surf_ha: 3177.0,
          aom_res_id: 3
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
