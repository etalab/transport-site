defmodule GBFS.VCubController do
  use GBFS, :controller
  require Logger
  alias Exshape.{Dbf, Shp}

  plug(:put_view, GBFS.FeedView)

  @static_url "https://data.bordeaux-metropole.fr/files.php?gid=43&format=2"
  @rt_url "https://data.bordeaux-metropole.fr/files.php?gid=105&format=2"

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
    |> render("gbfs.json")
  end

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
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(@rt_url),
         {:ok, z} <- :zip.zip_open(body, [:memory]),
         {:ok, {_, dbf_bin}} <- :zip.zip_get('CI_VCUB_P.dbf', z),
         dbf <- Dbf.read([dbf_bin]),
         _ <- :zip.zip_close(z) do
      %{
        stations:
          dbf
          |> Stream.reject(fn d -> match?(%Exshape.Dbf.Header{}, d) end)
          |> Stream.map(fn d ->
            [id, _, _, _, etat, num_docks_available, num_bikes_available | _] = d

            %{
              station_id: Integer.to_string(id),
              num_bikes_available: num_bikes_available,
              num_docks_available: num_docks_available,
              is_installed: 1,
              is_renting:
                if etat == "CONNECTEE" do
                  1
                else
                  0
                end,
              is_returning:
                if etat == "CONNECTEE" do
                  1
                else
                  0
                end,
              last_reported: DateTime.utc_now() |> DateTime.to_unix()
            }
          end)
          |> Enum.to_list()
      }
    end
  end

  defp get_station_information do
    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(@static_url),
         {:ok, z} <- :zip.zip_open(body, [:memory]),
         {:ok, {_, shp_bin}} <- :zip.zip_get('TB_STVEL_P.shp', z),
         {:ok, {_, dbf_bin}} <- :zip.zip_get('TB_STVEL_P.dbf', z),
         shp <- Shp.read([shp_bin]),
         dbf <- Dbf.read([dbf_bin]),
         stream <- Stream.zip(shp, dbf),
         _ <- :zip.zip_close(z) do
      %{
        stations:
          stream
          |> Stream.reject(fn {s, _} -> match?(%Exshape.Shp.Header{}, s) end)
          |> Stream.map(fn {s, d} ->
            [id, _, _, _, addr, city, _, _, nb_suppor, name | _] = d

            Map.merge(
              %{
                station_id: Integer.to_string(id),
                address: "#{String.trim(addr)} #{String.trim(city)}",
                name: String.trim(name),
                capacity: String.to_integer(String.trim(nb_suppor))
              },
              to_wgs84(s)
            )
          end)
          |> Enum.to_list()
      }
    end
  end

  # conversion from lambert93 to wgs84
  defp to_wgs84(%Exshape.Shp.PointZ{x: x, y: y}) do
    # constante de la projection
    c = 11_754_255.426096
    # première exentricité de l'ellipsoïde@
    e = 0.0818191910428158
    # exposant de la projection@
    n = 0.725607765053267
    # coordonnées en projection du pole@
    xs = 700_000
    # coordonnées en projection du pole@
    ys = 12_655_612.049876

    # pre-calcul
    a = :math.log(c / :math.sqrt(:math.pow(x - xs, 2) + :math.pow(y - ys, 2))) / n

    %{
      lon: (:math.atan(-(x - xs) / (y - ys)) / n + 3 / 180 * :math.pi()) / :math.pi() * 180,
      lat:
        :math.asin(
          :math.tanh(
            :math.log(c / :math.sqrt(:math.pow(x - xs, 2) + :math.pow(y - ys, 2))) / n +
              e *
                :math.atanh(
                  e *
                    :math.tanh(
                      a +
                        e *
                          :math.atanh(
                            e *
                              :math.tanh(
                                a +
                                  e *
                                    :math.atanh(
                                      e *
                                        :math.tanh(
                                          a +
                                            e *
                                              :math.atanh(
                                                e *
                                                  :math.tanh(
                                                    a +
                                                      e *
                                                        :math.atanh(
                                                          e *
                                                            :math.tanh(
                                                              a +
                                                                e *
                                                                  :math.atanh(
                                                                    e *
                                                                      :math.tanh(a + e * :math.atanh(e * :math.sin(1)))
                                                                  )
                                                            )
                                                        )
                                                  )
                                              )
                                        )
                                    )
                              )
                          )
                    )
                )
          )
        ) / :math.pi() * 180
    }
  end
end
