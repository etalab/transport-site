defmodule TransportWeb.AtomController do
  use TransportWeb, :controller
  alias DB.{Repo, Resource}
  import Ecto.Query

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    two_month_ago =
      "Etc/UTC"
      |> DateTime.now!()
      |> DateTime.add(-2 * 30 * 24 * 3600)

    resources = get_recently_updated_resources(two_month_ago)

    conn
    |> put_layout(false)
    |> put_resp_content_type("application/xml")
    |> render("index.html", resources: resources)
  end

  @spec get_recently_updated_resources(Calendar.datetime()) :: list
  def get_recently_updated_resources(limit_date) do
    Resource
    |> preload(:dataset)
    |> where([r], not is_nil(r.latest_url))
    |> Repo.all()
    |> Enum.filter(fn r ->
      case Timex.parse(r.last_update, "{ISO:Extended}") do
        {:ok, datetime} -> DateTime.compare(datetime, limit_date) == :gt
        _ -> false
      end
    end)
    |> Enum.sort(fn r1, r2 ->
      # we can use the ! version of parse, because of the filter above
      d1 = Timex.parse!(r1.last_update, "{ISO:Extended}")
      d2 = Timex.parse!(r2.last_update, "{ISO:Extended}")

      DateTime.compare(d1, d2) == :gt
    end)
  end
end
