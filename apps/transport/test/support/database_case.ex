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

        Repo.insert!(%Region{id: 1000, nom: "Pays de la Loire"})
        Repo.insert!(%Region{id: 1001, nom: "Auvergne-Rhône-Alpes"})
        Repo.insert!(%Region{id: 1002, nom: "Île-de-France"})

        Repo.insert!(%AOM{
          id: 1003,
          insee_commune_principale: "53130",
          nom: "Laval",
          region: Repo.get_by(Region, nom: "Pays de la Loire"),
          composition_res_id: 1
        })

        Repo.insert!(%AOM{
          id: 1004,
          insee_commune_principale: "38185",
          nom: "Grenoble",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes"),
          composition_res_id: 2
        })

        Repo.insert!(%AOM{
          id: 1005,
          insee_commune_principale: "36044",
          nom: "Châteauroux",
          region: Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes"),
          composition_res_id: 3
        })

        Repo.insert!(%Commune{
          id: 1006,
          insee: "38185",
          nom: "Grenoble",
          wikipedia: "fr:Grenoble",
          surf_ha: 200_554.0,
          aom_res_id: 2
        })

        Repo.insert!(%Commune{
          id: 1007,
          insee: "36044",
          nom: "Châteauroux",
          wikipedia: "fr:Châteauroux",
          surf_ha: 2554.0,
          aom_res_id: 3
        })

        Repo.insert!(%Commune{
          id: 1008,
          insee: "63096",
          nom: "Chas",
          wikipedia: "fr:Chas",
          surf_ha: 254.0,
          aom_res_id: 3
        })

        Repo.insert!(%AOM{
          id: 1009,
          insee_commune_principale: "75056",
          nom: "Île-de-France Mobilités",
          region: Repo.get_by(Region, nom: "Île-de-France"),
          composition_res_id: 4
        })

        Repo.insert!(%Commune{
          id: 1010,
          insee: "36063",
          nom: "Déols",
          wikipedia: "fr:Déols",
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
