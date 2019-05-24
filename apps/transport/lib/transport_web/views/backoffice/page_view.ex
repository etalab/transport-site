defmodule TransportWeb.Backoffice.PageView do
  use TransportWeb, :view
  alias TransportWeb.PaginationHelpers
  import TransportWeb.DatasetView, only: [end_date: 1]
  alias Transport.Dataset

  def pagination_links(conn, datasets) do
    kwargs = [path: &backoffice_page_path/3] |> add_filter(conn)

    PaginationHelpers.pagination_links(conn, datasets, kwargs)
  end

  defp add_filter(kwargs, %{params: %{"filter" => filter}}), do: Keyword.put(kwargs, :filter, filter)
  defp add_filter(kwargs, _), do: kwargs
end
