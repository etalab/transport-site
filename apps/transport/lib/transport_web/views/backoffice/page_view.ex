defmodule TransportWeb.Backoffice.PageView do
  use TransportWeb, :view
  alias TransportWeb.PaginationHelpers
  import TransportWeb.DatasetView, only: [end_date: 1]
  alias DB.Dataset

  def pagination_links(conn, datasets) do
    kwargs = [path: &backoffice_page_path/3] |> add_filter(conn)

    PaginationHelpers.pagination_links(conn, datasets, kwargs)
  end

  defp add_filter(kwargs, %{params: %{"filter" => filter} = p}) do
    kwargs
    |> Keyword.put(:filter, filter)
    |> add_filter(Map.drop(p, ["filter"]))
  end
  defp add_filter(kwargs, %{params: %{"q" => q} = p}) do
    kwargs
    |> Keyword.put(:q, q)
    |> add_filter(Map.drop(p, ["q"]))
  end
  defp add_filter(kwargs, _), do: kwargs
end
