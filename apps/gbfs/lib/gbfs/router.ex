defmodule GBFS.Router do
  use GBFS, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(CORSPlug, origin: "*", credentials: false)
    plug(PageCache, ttl_seconds: 30, cache_name: GBFS.Application.cache_name())
    plug(TransportWeb.Plugs.AppSignalFilter)
  end

  pipeline :jcdecaux do
    plug(:assign_jcdecaux)
  end

  pipeline :index_pipeline do
    plug(:assign_index)
  end

  @reseaux_jcdecaux %{
    "amiens" => "Velam",
    "besancon" => "VéloCité",
    "cergy-pontoise" => "Velo2",
    "creteil" => "CristoLib",
    "lyon" => "Vélo'v",
    "mulhouse" => "VéloCité",
    "nancy" => "vélOstan'lib",
    "nantes" => "Bicloo",
    "toulouse" => "Vélô"
  }

  scope "/gbfs", GBFS do
    pipe_through(:api)

    scope "/" do
      pipe_through(:index_pipeline)
      get("/", IndexController, :index)
    end

    scope "/vcub" do
      get("/gbfs.json", VCubController, :index)
      get("/system_information.json", VCubController, :system_information)
      get("/station_information.json", VCubController, :station_information)
      get("/station_status.json", VCubController, :station_status)
    end

    scope "/vlille" do
      get("/gbfs.json", VLilleController, :index)
      get("/system_information.json", VLilleController, :system_information)
      get("/station_information.json", VLilleController, :station_information)
      get("/station_status.json", VLilleController, :station_status)
    end

    @reseaux_jcdecaux
    |> Map.keys()
    |> Enum.map(fn contract ->
      scope "/" <> contract do
        pipe_through(:jcdecaux)

        get("/gbfs.json", JCDecauxController, :index, as: contract)
        get("/system_information.json", JCDecauxController, :system_information, as: contract)
        get("/station_information.json", JCDecauxController, :station_information, as: contract)
        get("/station_status.json", JCDecauxController, :station_status, as: contract)
      end
    end)
  end

  defp assign_jcdecaux(conn, _) do
    [_, contract_id, _] = conn.path_info

    conn
    |> assign(:contract_id, contract_id)
    |> assign(:contract_name, @reseaux_jcdecaux[contract_id])
  end

  defp assign_index(conn, _) do
    conn
    |> assign(
      :networks,
      ["vcub", "vlille"] ++ (@reseaux_jcdecaux |> Map.keys())
    )
  end
end
