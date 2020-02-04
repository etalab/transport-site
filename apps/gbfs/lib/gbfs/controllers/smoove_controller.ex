defmodule GBFS.SmooveController do
  use GBFS, :controller
  import SweetXml
  require Logger

  plug(:put_view, GBFS.FeedView)

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    contract_id = conn.assigns.smoove_params.contract_id

    conn
    |> assign(
      :data,
      %{
        "fr" => %{
          "feeds" =>
            Enum.map(
              [:system_information, :station_information, :station_status],
              fn a ->
                %{
                  "name" => Atom.to_string(a),
                  "url" => apply(Routes, String.to_atom("#{contract_id}_url"), [conn, a])
                }
              end
            )
        }
      }
    )
    |> render("gbfs.json")
  end

  @spec system_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def system_information(conn, _params) do
    smoove_params = conn.assigns.smoove_params

    conn
    |> assign(
      :data,
      %{
        "system_id" => smoove_params.contract_id,
        "language" => "fr",
        "name" => smoove_params.nom,
        "timezone" => "Europe/Paris"
      }
    )
    |> render("gbfs.json")
  end

  @spec station_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_information(conn, _params) do
    url = conn.assigns.smoove_params.url

    conn
    |> assign(:data, get_station_information(url))
    |> render("gbfs.json")
  end

  @spec station_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_status(conn, _params) do
    url = conn.assigns.smoove_params.url

    conn
    |> assign(:data, get_station_status(url))
    |> render("gbfs.json")
  end

  @spec get_station_status(binary()) :: map()
  defp get_station_status(url) do
    %{
      "stations" =>
        url
        |> get_stations()
        |> Enum.map(&Map.take(&1, [:station_id, :capacity, :num_bikes_available, :num_docks_available, :credit_card]))
        |> Enum.map(&Map.put(&1, :is_installed, 1))
        |> Enum.map(&Map.put(&1, :is_returning, 1))
        |> Enum.map(&Map.put(&1, :last_reported, DateTime.utc_now() |> DateTime.to_unix()))
        |> Enum.map(
          &Map.put(
            &1,
            :is_renting,
            if(Map.has_key?(&1, :credit_card), do: 1, else: 0)
          )
        )
        |> Enum.map(&Map.delete(&1, :credit_card))
    }
  end

  @spec get_station_information(binary()) :: map()
  defp get_station_information(url) do
    %{
      "stations" =>
        url
        |> get_stations()
        |> Enum.map(&Map.take(&1, [:name, :station_id, :lat, :lon, :capacity, :credit_card]))
        |> Enum.map(&set_rental_method/1)
        |> Enum.map(&Map.delete(&1, :credit_card))
    }
  end

  @spec set_rental_method(map()) :: map()
  defp set_rental_method(%{credit_card: 1} = station), do: Map.put(station, :rental_method, "CREDIT_CARD")
  defp set_rental_method(station), do: station

  @spec get_stations(binary()) :: map()
  defp get_stations(url) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(url),
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
        Logger.error("Unable to decode body")
        nil

      error ->
        Logger.error(error)
        nil
    end
  end
end
