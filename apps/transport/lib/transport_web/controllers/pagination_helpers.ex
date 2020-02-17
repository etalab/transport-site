defmodule TransportWeb.PaginationHelpers do
  @moduledoc """
  Helpers pour la pagination utlisés par différentes pages
  """
  alias Scrivener.HTML

  def make_pagination_config(%{"page" => page_number}) do
    page_number =
      case Integer.parse(page_number) do
        :error -> 1
        {int, _} -> int
      end

    %Scrivener.Config{page_number: page_number, page_size: 10}
  end

  def make_pagination_config(_), do: %Scrivener.Config{page_number: 1, page_size: 10}

  def pagination_links(_, %{total_pages: 1}), do: ""

  def pagination_links(conn, paginator) do
    conn.params
    |> remove_empty_q()
    |> case do
      [] -> HTML.pagination_links(conn, paginator)
      args -> HTML.pagination_links(conn, paginator, args)
    end
  end

  def pagination_links(_, %{total_pages: 1}, _), do: ""

  def pagination_links(conn, paginator, opts) do
    opts
    |> remove_empty_q
    |> case do
      [] -> HTML.pagination_links(conn, paginator, opts)
      opts -> HTML.pagination_links(conn, paginator, opts)
    end
  end

  def pagination_links(_, %{total_pages: 1}, _, _), do: ""

  def pagination_links(conn, paginator, args, opts) do
    opts
    |> remove_empty_q()
    |> case do
      [] -> HTML.pagination_links(conn, paginator, opts)
      opts -> HTML.pagination_links(conn, paginator, args, opts)
    end
  end

  defp remove_empty_q(args) when is_map(args) do
    remove_empty_q(for {key, value} <- args, do: {String.to_atom(key), value})
  end

  defp remove_empty_q(args) do
    args = Keyword.delete(args, :page)

    case Keyword.get(args, :q) do
      "" -> Keyword.delete(args, :q)
      _ -> args
    end
  end
end
