defmodule GBFS.JCDecauxController do
  use GBFS, :controller

  plug :put_view, GBFS.FeedView

  defp rt_url(contract_name) do
    api_key = Application.get_env(:gbfs, :jcdecaux_apikey)
    "https://api.jcdecaux.com/vls/v1/stations?contract=#{contract_name}&apiKey=#{api_key}"
  end

  def index(%{assigns: %{contract_id: contract}} = conn, _) do
    conn
    |> assign(:data,
      %{
        "fr" => %{
          "feeds" =>
            Enum.map([:system_information, :station_information, :station_status],
              fn a ->
                %{
                  "name" => Atom.to_string(a),
                  "url" => apply(Routes, String.to_atom(contract <> "_url"), [conn, a])
                } end
          )
        }
      }
    )
    |> render("gbfs.json")
  end

  def system_information(%{assigns: %{contract_id: id, contract_name: name}} = conn, _params) do
    conn
    |> assign(:data,
      %{
        "system_id" => id,
        "language" => "fr",
        "name" => name,
        "timezone" => "Europe/Paris"
      }
    )
    |> render("gbfs.json")
  end

  def station_information(%{assigns: %{contract_id: contract}} = conn, _params) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(rt_url(contract)),
        {:ok, json} <- Jason.decode(body) do
        conn
        |> assign(:data,
          %{
            stations: Enum.map(json, fn s -> %{
              station_id: s["number"] |> Integer.to_string(),
              name: s["name"],
              lat: s["position"]["lat"],
              lon: s["position"]["lng"],
              address: s["address"],
              capacity: s["bike_stands"],
            } end)
          }
        )
        |> render("gbfs.json")
    else
      _ -> render(conn, GBFS.ErrorView, "error.json", %{error: "Unable to read source file"})
    end
  end

  def station_status(%{assigns: %{contract_id: contract}} = conn, _params) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(rt_url(contract)),
        {:ok, json} <- Jason.decode(body) do
        conn
        |> assign(:data,
          %{
            stations: Enum.map(json, fn s -> %{
              station_id: s["number"] |> Integer.to_string(),
              num_bikes_available: s["available_bikes"],
              num_docks_available: s["available_bike_stands"],
              is_installed: if s["status"] == "OPEN" do 1 else 0 end,
              is_renting: if s["status"] == "OPEN" do 1 else 0 end,
              is_returning: if s["status"] == "OPEN" do 1 else 0 end,
              last_reported: s["last_update"] / 1000
            } end)
          }
        )
        |> render("gbfs.json")
    else
      _ -> render(conn, GBFS.ErrorView, "error.json", %{error: "Unable to read source file"})
    end
  end
end
