defmodule TransportWeb.PaginationHelpers do
  @moduledoc """
  Builds the `Scrivener.Config` used to paginate Ecto queries and lists (validation issues), from the `page` param.

  The page size is chosen by the caller: a `page_size` param in the request is ignored, unlike with
  `Scrivener.Config.new/3`, which would let anyone request huge pages.

  Any `page` that is not a number between 1 and 1,000,000 falls back to 1: lists and NeTEx results
  would otherwise slice from the end on page 0 or below, and huge numbers crash Explorer.
  """

  @max_page_number 1_000_000

  def make_pagination_config(params, page_size \\ 20)

  def make_pagination_config(%{"page" => page_number}, page_size) when is_binary(page_number) do
    page_number =
      case Integer.parse(page_number) do
        {int, _} when int in 1..@max_page_number -> int
        _ -> 1
      end

    %Scrivener.Config{page_number: page_number, page_size: page_size}
  end

  def make_pagination_config(_, page_size), do: %Scrivener.Config{page_number: 1, page_size: page_size}
end
