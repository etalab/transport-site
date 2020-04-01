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

    sort_arrow = get_arrow(current_order.field == order_by, current_order.direction)
    link(raw("#{text} #{sort_arrow}"), to: full_url)
  end

  @spec get_arrow(boolean, atom) :: <<_::64, _::_*8>>
  defp get_arrow(column_is_sorted, direction) do
    case {column_is_sorted, direction} do
      {false, _} ->
        "<i class=\"sort-icon fa fa-sort\"></i>"

      {true, :asc} ->
        "<i class=\"sort-icon fa fa-sort-up\"></i>"

      {true, :desc} ->
        "<i class=\"sort-icon fa fa-sort-down\"></i>"
    end
  end
end
