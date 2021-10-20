defmodule GBFS.SmooveController do
  use GBFS, :controller
  import SweetXml
  require Logger

  plug(:put_view, GBFS.FeedView)
  @gbfs_version "1.1"

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    contract_id = conn.assigns.smoove_params.contract_id

    {:ok,
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
     }}
    |> render_response(conn)
  end

  @spec system_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def system_information(conn, _params) do
    smoove_params = conn.assigns.smoove_params

    {:ok,
     %{
       "system_id" => smoove_params.contract_id,
       "language" => "fr",
       "name" => smoove_params.nom,
       "timezone" => "Europe/Paris"
     }}
    |> render_response(conn)
  end

  @spec station_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_information(conn, _params) do
    conn.assigns.smoove_params.url |> get_station_information() |> render_response(conn)
  end

  @spec station_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_status(conn, _params) do
    conn.assigns.smoove_params.url |> get_station_status() |> render_response(conn)
  end

  @spec get_station_status(binary()) :: {:ok, map()} | {:error, binary()}
  defp get_station_status(url) do
    case get_stations(url) do
      {:ok, data} ->
        {:ok,
         %{
           "stations" =>
             data
             |> Enum.map(
               &Map.take(&1, [:station_id, :capacity, :num_bikes_available, :num_docks_available, :credit_card])
             )
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
         }}

      {:error, e} ->
        {:error, e}
    end
  end

  @spec get_station_information(binary()) :: {:ok, map()} | {:error, binary()}
  defp get_station_information(url) do
    case get_stations(url) do
      {:ok, data} ->
        {:ok,
         %{
           "stations" =>
             data
             |> Enum.map(&Map.take(&1, [:name, :station_id, :lat, :lon, :capacity, :credit_card]))
             |> Enum.map(&set_rental_method/1)
             |> Enum.map(&Map.delete(&1, :credit_card))
         }}

      {:error, e} ->
        {:error, e}
    end
  end

  @spec set_rental_method(map()) :: map()
  defp set_rental_method(%{credit_card: 1} = station), do: Map.put(station, :rental_method, "CREDIT_CARD")
  defp set_rental_method(station), do: station

  @spec get_stations(binary()) :: {:ok, map()} | {:error, binary()}
  defp get_stations(url) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(url),
         body when not is_nil(body) <- :iconv.convert("iso8859-1", "latin1", body) do
      {:ok,
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
       )}
    else
      e ->
        Logger.error("impossible to query smoove: #{inspect(e)}")
        {:error, "smoove service unavailable"}
    end
  end

  defp render_response({:ok, data}, conn),
    do:
      conn
      |> assign(:data, data)
      |> assign(:version, @gbfs_version)
      |> render("gbfs.json")

  defp render_response({:error, msg}, conn),
    do:
      conn
      |> assign(:error, msg)
      # for the moment we always return a BAD_GATEWAY in case of error
      |> put_status(502)
      |> put_view(GBFS.ErrorView)
      |> render("error.json")
end
