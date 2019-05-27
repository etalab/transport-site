defmodule GBFS.VelomaggController do
  use GBFS, :controller
  import SweetXml
  require Logger

  plug :put_view, GBFS.FeedView

  @url "https://data.montpellier3m.fr/sites/default/files/ressources/TAM_MMM_VELOMAG.xml"

  def index(conn, _params) do
    conn
    |> assign(:data,
      %{
        "fr" => %{
          "feeds" =>
          Enum.map([:system_information, :station_information, :station_status],
            fn a -> %{"name" => Atom.to_string(a), "url" => Routes.velomagg_url(conn, a)} end
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
        "system_id" => "velomagg",
        "language" => "fr",
        "name" => "Velomagg",
        "timezone" => "Europe/Paris"
      }
    )
    |> render("gbfs.json")
  end

  def station_information(conn, _params) do
    conn
    |> assign(:data, get_station_information())
    |> render("gbfs.json")
  end

  def station_status(conn, _params) do
    conn
    |> assign(:data, get_station_status())
    |> render("gbfs.json")
  end

  defp get_station_status do
    %{"stations" =>
      get_stations()
      |> Enum.map(
        & Map.take(&1, [:station_id, :capacity, :num_bikes_available,
         :num_docks_available, :credit_card])
      )
      |> Enum.map(& Map.put(&1, :is_installed, 1))
      |> Enum.map(& Map.put(&1, :is_returning, 1))
      |> Enum.map(& Map.put(&1, :last_reported, DateTime.utc_now() |> DateTime.to_unix()))
      |> Enum.map(& Map.put(&1, :is_renting, if Map.has_key?(&1, :credit_card) do 1 else 0 end))
      |> Enum.map(& Map.delete(&1, :credit_card))
    }
  end

  defp get_station_information do
    %{"stations" =>
      get_stations()
      |> Enum.map(
        & Map.take(&1, [:name, :station_id, :lat, :lon, :capacity, :credit_card])
      )
      |> Enum.map(&set_rental_method/1)
      |> Enum.map(& Map.delete(&1, :credit_card))
    }
  end

  defp set_rental_method(%{credit_card: 1} = station) do
    Map.put(station, :rental_method, "CREDIT_CARD")
  end
  defp set_rental_method(station), do: station

  defp get_stations do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(@url),
      body when not is_nil(body) <- :iconv.convert("iso8859-1", "latin1", body) do
        body
        |> xpath(~x"//si"l,
          name: ~x"@na"S,
          station_id: ~x"@id"s,
          lat: ~x"@la"f,
          lon: ~x"@lg"f,
          capacity: ~x"@to"i,
          credit_card: ~x"@cb"I,
          num_bikes_available: ~x"@av"i,
          num_docks_available: ~x"@fr"i
        )
    else
      nil ->
        Logger.error "Unable to decode body"
        nil
      error ->
        Logger.error(error)
        nil
    end
  end
end
