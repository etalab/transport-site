defmodule GBFS.VCubController do
  use GBFS, :controller
  require Logger

  plug(:put_view, GBFS.FeedView)

  @rt_url "https://opendata.bordeaux-metropole.fr/api/records/1.0/search/?dataset=ci_vcub_p&q=&rows=10000"
  @gbfs_version "2.0"
  @ttl 60

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    conn
    |> assign(
      :data,
      %{
        "fr" => %{
          "feeds" =>
            Enum.map(
              [:system_information, :station_information, :station_status],
              fn a -> %{"name" => Atom.to_string(a), "url" => Routes.v_cub_url(conn, a)} end
            )
        }
      }
    )
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
        "system_id" => "vcub",
        "language" => "fr",
        "name" => "VCub",
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
        |> render(GBFS.ErrorView, "error.json")
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
          {:ok, dt, _offset} = DateTime.from_iso8601(r["fields"]["mdate"])
          last_reported = DateTime.to_unix(dt)

          %{
            station_id: r["fields"]["ident"],
            num_bikes_available: to_int(r["fields"]["nbvelos"]),
            num_docks_available: to_int(r["fields"]["nbplaces"]),
            is_renting: r["fields"]["etat"] == "CONNECTEE",
            is_returning: r["fields"]["etat"] == "CONNECTEE",
            last_reported: last_reported
          }
        end)

      %{stations: stations}
    end

    get_information_aux(convert_station_status)
  end

  @spec to_int(integer() | binary) :: integer()
  defp to_int(i) when is_integer(i), do: i

  defp to_int(s) when is_binary(s), do: String.to_integer(s)

  @spec get_station_information() :: {:ok, %{stations: [map()]}} | {:error, binary}
  defp get_station_information do
    convert_station_information = fn records ->
      stations =
        Enum.map(records, fn r ->
          [lon, lat] = r["geometry"]["coordinates"]

          %{
            station_id: r["fields"]["ident"],
            name: r["fields"]["nom"],
            lat: lon,
            lon: lat,
            post_code: r["fields"]["code_commune"],
            capacity: to_int(r["fields"]["nbvelos"]) + to_int(r["fields"]["nbplaces"])
          }
        end)

      %{stations: stations}
    end

    get_information_aux(convert_station_information)
  end

  @spec get_information_aux((map -> map)) :: {:ok, map()} | {:error, binary}
  defp get_information_aux(convert_func) do
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(@rt_url),
         {:ok, data} <- Jason.decode(body) do
      res = convert_func.(data["records"])
      {:ok, res}
    else
      _ -> {:error, "service unavailable"}
    end
  end
end
