defmodule TransportWeb.PaginationHelpers do
  @moduledoc """
  Helpers pour la pagination utlisés par différentes pages
  """
  alias Scrivener.HTML

  def make_pagination_config(params, page_size \\ 20)

  def make_pagination_config(%{"page" => page_number}, page_size) do
    page_number =
      case Integer.parse(page_number) do
        :error -> 1
        {int, _} -> int
      end

    %Scrivener.Config{page_number: page_number, page_size: page_size}
  end

  def make_pagination_config(_, page_size), do: %Scrivener.Config{page_number: 1, page_size: page_size}

  def pagination_links(_, %{total_pages: 1}), do: {:safe, ""}

  def pagination_links(conn, paginator) do
    case remove_empty_q(conn.params) do
      [] -> HTML.pagination_links(conn, paginator, view_style: :bootstrap_v4)
      args -> HTML.pagination_links(conn, paginator, [view_style: :bootstrap_v4] ++ args)
    end
  end

  def pagination_links(_, %{total_pages: 1}, _), do: {:safe, ""}

  def pagination_links(conn, paginator, opts) do
    case remove_empty_q(opts) do
      [] -> HTML.pagination_links(conn, paginator, view_style: :bootstrap_v4)
      opts -> HTML.pagination_links(conn, paginator, [view_style: :bootstrap_v4] ++ opts)
    end
  end

  def pagination_links(_, %{total_pages: 1}, _, _), do: {:safe, ""}

  def pagination_links(conn, paginator, args, opts) do
    case remove_empty_q(opts) do
      [] -> HTML.pagination_links(conn, paginator, args, view_style: :bootstrap_v4)
      opts -> HTML.pagination_links(conn, paginator, args, [view_style: :bootstrap_v4] ++ opts)
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
