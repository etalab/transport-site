defmodule TransportWeb.Backoffice.ContactView do
  use TransportWeb, :view
  alias TransportWeb.PaginationHelpers

  def pagination_links(conn, contacts) do
    kwargs = [path: &backoffice_contact_path/3] |> add_filter(conn.params)

    PaginationHelpers.pagination_links(conn, contacts, kwargs)
  end

  @spec add_filter(list, map) :: list
  defp add_filter(kwargs, params) do
    params
    |> Map.take(["q"])
    |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Enum.concat(kwargs)
  end
end
