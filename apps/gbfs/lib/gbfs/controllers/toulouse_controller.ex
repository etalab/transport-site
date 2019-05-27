defmodule GBFS.ToulouseController do
  use GBFS, :controller
  require Logger

  plug :put_view, GBFS.FeedView

  @contract_name "toulouse"

  defp api_key, do: Application.get_env(:gbfs, :jcdecaux_apikey)
  defp rt_url, do: "https://api.jcdecaux.com/vls/v1/stations?contract=#{@contract_name}&apiKey=#{api_key()}"

  def index(conn, _params) do
    conn
    |> assign(:data,
      %{
        "fr" => %{
          "feeds" =>
          Enum.map([:system_information, :station_information, :station_status],
            fn a -> %{"name" => Atom.to_string(a), "url" => Routes.toulouse_url(conn, a)} end
          )
        }
      }
    )
    |> render("gbfs.json")
  end

  def system_information(conn, _params) do
    conn
    |> assign(:data,
      %{
        "system_id" => "toulouse",
        "language" => "fr",
        "name" => "Toulouse",
        "timezone" => "Europe/Paris"
      }
    )
    |> render("gbfs.json")
  end

  def station_information(conn, _params) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(rt_url()),
        {:ok, json} <- Jason.decode(body) do
        conn
        |> assign(:data,
          %{
            stations: Enum.map(json, fn s -> %{
              station_id: s["number"],
              name: s["name"],
              lat: s["latitude"],
              lon: s["longitude"],
              address: s["address"]
            } end)
          }
        )
        |> render("gbfs.json")
    else
      _ -> render(conn, GBFS.ErrorView, "error.json", %{error: "Unable to read source file"})
    end
  end

  def station_status(conn, _params) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(rt_url()),
        {:ok, json} <- Jason.decode(body) do
        conn
        |> assign(:data,
          %{
            stations: Enum.map(json, fn s -> %{
              station_id: s["number"],
              num_bikes_available: s["available_bikes"],
              num_docks_available: s["available_bike_stands"],
              is_installed: if s["status"] == "OPEN" do 1 else 0 end,
              is_renting: if s["status"] == "OPEN" do 1 else 0 end,
              is_returning: if s["status"] == "OPEN" do 1 else 0 end,
              last_reported: s["last_update"]
            } end)
          }
        )
        |> render("gbfs.json")
    else
      _ -> render(conn, GBFS.ErrorView, "error.json", %{error: "Unable to read source file"})
    end
  end
end
