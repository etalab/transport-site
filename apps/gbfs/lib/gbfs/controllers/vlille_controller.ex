defmodule GBFS.VLilleController do
  use GBFS, :controller
  require Logger
  alias GBFS.ControllerHelpers

  plug(:put_view, GBFS.FeedView)

  @rt_url "https://www.data.gouv.fr/fr/datasets/r/6d66af27-7a26-4263-b610-4ecf5fb34369"
  @gbfs_version "2.0"
  @ttl 60

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    conn
    |> ControllerHelpers.assign_data_gbfs_json(&Routes.v_lille_url/2)
    |> assign(:version, @gbfs_version)
    |> assign(:ttl, @ttl)
    |> render("gbfs.json")
  end

  @spec system_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def system_information(conn, _params) do
    conn
    |> assign(
      :data,
      %{
        "system_id" => "vlille",
        "language" => "fr",
        "name" => "V'Lille",
        "timezone" => "Europe/Paris"
      }
    )
    |> assign(:version, @gbfs_version)
    |> assign(:ttl, @ttl)
    |> render("gbfs.json")
  end

  @spec station_aux(Plug.Conn.t(), (() -> {:ok, map()} | {:error, binary()})) :: Plug.Conn.t()
  defp station_aux(conn, get_info_function) do
    case get_info_function.() do
      {:ok, data} ->
        conn
        |> assign(:data, data)
        |> assign(:ttl, @ttl)
        |> assign(:version, @gbfs_version)
        |> render("gbfs.json")

      {:error, msg} ->
        conn
        |> assign(:error, msg)
        |> put_status(502)
        |> put_view(GBFS.ErrorView)
        |> render("error.json")
    end
  end

  @spec station_information(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_information(conn, _params) do
    station_aux(conn, &get_station_information/0)
  end

  @spec station_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def station_status(conn, _params) do
    station_aux(conn, &get_station_status/0)
  end

  @spec get_station_status() :: {:ok, %{stations: [map()]}} | {:error, binary}
  defp get_station_status do
    convert_station_status = fn records ->
      stations =
        Enum.map(records, fn r ->
          {:ok, dt, _offset} =
            try do
              DateTime.from_iso8601(r["fields"]["datemiseajour"])
            rescue
              e ->
                Sentry.capture_exception(e,
                  stacktrace: __STACKTRACE__,
                  extra: %{extra: "r[\"fields\"] value is #{inspect(r["fields"])}"}
                )

                reraise e, __STACKTRACE__
            end

          last_reported = DateTime.to_unix(dt)
          is_open = r["fields"]["etat"] == "EN SERVICE"

          %{
            station_id: r["recordid"],
            num_bikes_available: r["fields"]["nbvelosdispo"],
            num_docks_available: r["fields"]["nbplacesdispo"],
            is_installed: is_open,
            is_renting: is_open,
            is_returning: is_open,
            last_reported: last_reported
          }
        end)

      %{stations: stations}
    end

    get_information_aux(convert_station_status)
  end

  @spec get_station_information() :: {:ok, %{stations: [map()]}} | {:error, binary}
  defp get_station_information do
    convert_station_information = fn records ->
      stations =
        Enum.map(records, fn r ->
          [lat, lon] = r["geometry"]["coordinates"]

          %{
            station_id: r["recordid"],
            name: r["fields"]["nom"],
            lat: lon,
            lon: lat,
            address: r["fields"]["adresse"] <> ", " <> r["fields"]["commune"],
            capacity: r["fields"]["nbvelosdispo"] + r["fields"]["nbplacesdispo"]
          }
        end)

      %{stations: stations}
    end

    get_information_aux(convert_station_information)
  end

  @spec get_information_aux((map -> map)) :: {:ok, map()} | {:error, binary}
  defp get_information_aux(convert_func) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    with {:ok, %HTTPoison.Response{status_code: status_code, body: body}}
         when status_code >= 200 and status_code < 400 <-
           http_client.get(@rt_url, [], hackney: [follow_redirect: true]),
         {:ok, data} <- Jason.decode(body) do
      res = convert_func.(data)
      {:ok, res}
    else
      _ -> {:error, "VLille service unavailable"}
    end
  end
end
