defmodule TransportWeb.PaginationHelpers do
  @moduledoc """
  Helpers pour la pagination utlisés par différentes pages
  """

  def make_pagination_config(%{"page" => page_number}) do
    page_number = case Integer.parse(page_number) do
      :error -> 1
      {int, _} -> int
    end

    %Scrivener.Config{page_number: page_number, page_size: 10}
  end
  def make_pagination_config(_), do: %Scrivener.Config{page_number: 1, page_size: 10}
end
