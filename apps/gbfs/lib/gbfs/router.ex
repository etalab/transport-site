defmodule GBFS.Router do
  use GBFS, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :jcdecaux do
    plug :assign_contract_name
  end

  @reseaux_jcdecaux %{
    "amiens" => "Velam",
    "cergy-pontoise" => "Velo2",
    "creteil" => "CristoLib",
    "lyon" => "Vélo'v",
    "marseille" => "Le vélo",
    "mulhouse" => "VéloCité",
    "nancy" => "vélOstan'lib",
    "nantes" => "Bicloo",
    "rouen" => "cy'clic",
    "toulouse" => "Vélô",
  }

  scope "/gbfs", GBFS do
    pipe_through :api

    scope "/velomagg" do
      get "/gbfs.json", VelomaggController, :index
      get "/system_information.json", VelomaggController, :system_information
      get "/station_information.json", VelomaggController, :station_information
      get "/station_status.json", VelomaggController, :station_status
    end

    @reseaux_jcdecaux
    |> Map.keys()
    |> Enum.map(
      fn contract ->
        scope "/"<> contract do
          pipe_through :jcdecaux

          get "/gbfs.json", JCDecauxController, :index, as: contract
          get "/system_information.json", JCDecauxController, :system_information, as: contract
          get "/station_information.json", JCDecauxController, :station_information, as: contract
          get "/station_status.json", JCDecauxController, :station_status, as: contract
        end
      end
    )
  end

  defp assign_contract_name(conn, _) do
    [_, contract_id, _] = conn.path_info

    conn
    |> assign(:contract_id, contract_id)
    |> assign(:contract_name, @reseaux_jcdecaux[contract_id])
  end
end
