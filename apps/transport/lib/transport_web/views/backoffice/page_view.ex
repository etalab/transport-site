defmodule TransportWeb.Backoffice.PageView do
  use TransportWeb, :view
  alias Plug.Conn.Query
  alias TransportWeb.PaginationHelpers
  import TransportWeb.DatasetView, only: [end_date: 1]
  alias DB.Dataset

  def pagination_links(conn, datasets) do
    kwargs = [path: &backoffice_page_path/3] |> add_filter(conn.params)

    PaginationHelpers.pagination_links(conn, datasets, kwargs)
  end

  @spec add_filter(list, map) :: list
  defp add_filter(kwargs, params) do
    params
    # filter allowed keys
    |> Map.take(["filter", "q", "order_by", "dir"])
    |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Enum.concat(kwargs)
  end

  @spec backoffice_sort_link(Plug.Conn.t(), String.t(), atom, %{field: atom, direction: atom}) ::
          any
  def backoffice_sort_link(conn, text, order_by, current_order) do
    dir =
      case current_order.field == order_by do
        false ->
          :asc

        true ->
          case current_order.direction do
            :asc -> :desc
            _ -> :asc
          end
      end

    params =
      conn.query_params
      |> Map.put("order_by", order_by)
      |> Map.put("dir", dir)

    full_url =
      conn.request_path
      |> URI.parse()
      |> Map.put(:query, Query.encode(params))
      |> URI.to_string()
      |> Kernel.<>("#backoffice-datasets-table")

    link(text, to: full_url)
  end

  @spec get_arrow(boolean, atom) :: String.t()
  def get_arrow(show, direction) do
    case {show, direction} do
      {false, _} ->
        ""

      {true, :asc} ->
        ~E"<i class=\"fa fa-long-arrow-alt-down\"></i>"

      {true, :desc} ->
        ~E"<i class=\"fa fa-long-arrow-alt-up\"></i>"
    end
  end
end
