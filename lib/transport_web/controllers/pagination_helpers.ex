defmodule TransportWeb.PaginationHelpers do
  @moduledoc """
  Helpers pour la pagination utlisés par différentes pages
  """
  alias Scrivener.HTML

  def make_pagination_config(%{"page" => page_number}) do
    page_number = case Integer.parse(page_number) do
      :error -> 1
      {int, _} -> int
    end

    %Scrivener.Config{page_number: page_number, page_size: 10}
  end
  def make_pagination_config(_), do: %Scrivener.Config{page_number: 1, page_size: 10}

  def pagination_links(_, %{total_pages: 1}, _), do: ""
  def pagination_links(conn, paginator, args) do
    args
    |> remove_empty_q()
    |> case do
      [] -> HTML.pagination_links(conn, paginator)
      _ -> HTML.pagination_links(conn, paginator, args)
    end
  end

  def pagination_links(conn, paginator, args, opts) do
    args
    |> remove_empty_q()
    |> case do
      [] -> HTML.pagination_links(conn, paginator, opts)
      _ -> HTML.pagination_links(conn, paginator, args, opts)
    end
  end

  defp remove_empty_q(args) do
    case Keyword.get(args, :q) do
      "" -> Keyword.delete(args, :q)
      _ -> args
    end
  end
end
