defmodule GBFS.Router do
  use GBFS, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(CORSPlug, origin: "*", credentials: false)
    plug(TransportWeb.Plugs.AppSignalFilter)
  end

  pipeline :page_cache do
    # Cache results and send telemetry events, storing metrics
    plug(PageCache, ttl_seconds: 30, cache_name: GBFS.Application.cache_name())
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
    pipe_through([:api, :page_cache])

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

    scope "/" do
      pipe_through(:index_pipeline)
      get("/", IndexController, :index)
    end
  end

  scope "/gbfs", GBFS do
    # Only the `:api` pipeline, we don't want to cache the response or send telemetry events
    pipe_through(:api)
    get("/*path", IndexController, :not_found)
  end

  defp assign_jcdecaux(conn, _) do
    [_, contract_id, _] = conn.path_info

    conn
    |> assign(:contract_id, contract_id)
    |> assign(:contract_name, @reseaux_jcdecaux[contract_id])
  end

  defp assign_index(conn, _) do
    assign(conn, :networks, Map.keys(@reseaux_jcdecaux))
  end
end
