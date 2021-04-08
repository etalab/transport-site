defmodule GBFS.JCDecauxController do
  use GBFS, :controller
  require Logger

  plug(:put_view, GBFS.FeedView)
  @gbfs_version "1.1"

  @spec rt_url(binary()) :: binary()
  defp rt_url(contract_name) do
    api_key = Application.get_env(:gbfs, :jcdecaux_apikey)
    "https://api.jcdecaux.com/vls/v1/stations?contract=#{contract_name}&apiKey=#{api_key}"
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%{assigns: %{contract_id: contract}} = conn, _) do
    {:ok,
     %{
       "fr" => %{
         "feeds" =>
           Enum.map(
             [:system_information, :station_information, :station_status],
             fn a ->
               %{
                 "name" => Atom.to_string(a),
                 "url" => apply(Routes, String.to_atom(contract <> "_url"), [conn, a])
               }
             end
           )
       }
     }}
    |> render_response(conn)
  end

  @spec system_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def system_information(%{assigns: %{contract_id: id, contract_name: name}} = conn, _params) do
    {:ok,
     %{
       "system_id" => id,
       "language" => "fr",
       "name" => name,
       "timezone" => "Europe/Paris"
     }}
    |> render_response(conn)
  end

  @spec convert_station_information({:ok, map()} | {:error, binary()}) :: {:ok, map()} | {:error, binary()}
  defp convert_station_information({:ok, json}),
    do:
      {:ok,
       %{
         stations:
           Enum.map(json, fn s ->
             %{
               station_id: s["number"] |> Integer.to_string(),
               name: s["name"],
               lat: s["position"]["lat"],
               lon: s["position"]["lng"],
               address: s["address"],
               capacity: s["bike_stands"]
             }
           end)
       }}

  defp convert_station_information({:error, msg}), do: {:error, msg}

  @spec station_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_information(%{assigns: %{contract_id: contract}} = conn, _params) do
    contract
    |> query_jcdecaux()
    |> convert_station_information()
    |> render_response(conn)
  end

  @spec query_jcdecaux(binary()) :: {:ok, map()} | {:error, binary()}
  def query_jcdecaux(contract) do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(rt_url(contract)),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      e ->
        Logger.error("impossible to query jcdecaux: #{inspect(e)}")
        {:error, "jcdecaux service unavailable"}
    end
  end

  @spec convert_station_status({:ok, map()} | {:error, binary()}) :: {:ok, map()} | {:error, binary()}
  defp convert_station_status({:ok, json}),
    do:
      {:ok,
       %{
         stations:
           Enum.map(json, fn s ->
             %{
               station_id: s["number"] |> Integer.to_string(),
               num_bikes_available: s["available_bikes"],
               num_docks_available: s["available_bike_stands"],
               is_installed: if(s["status"] == "OPEN", do: 1, else: 0),
               is_renting: if(s["status"] == "OPEN", do: 1, else: 0),
               is_returning: if(s["status"] == "OPEN", do: 1, else: 0),
               last_reported: s["last_update"] / 1000
             }
           end)
       }}

  defp convert_station_status({:error, msg}), do: {:error, msg}

  @spec station_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_status(%{assigns: %{contract_id: contract}} = conn, _params) do
    contract
    |> query_jcdecaux()
    |> convert_station_status()
    |> render_response(conn)
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
