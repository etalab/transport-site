defmodule TransportWeb.PaginationHelpers do
  @moduledoc """
  Builds the `Scrivener.Config` used to paginate Ecto queries and lists (validation issues), from the `page` param.

  The page size is chosen by the caller: a `page_size` param in the request is ignored, unlike with
  `Scrivener.Config.new/3`, which would let anyone request huge pages.
  """

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
end
