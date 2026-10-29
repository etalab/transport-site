defmodule TransportWeb.PaginationHelpersTest do
  use ExUnit.Case, async: true

  test "page and page size" do
    assert %Scrivener.Config{page_number: 3, page_size: 20} =
             TransportWeb.PaginationHelpers.make_pagination_config(%{"page" => "3"})

    assert %Scrivener.Config{page_number: 1, page_size: 10} =
             TransportWeb.PaginationHelpers.make_pagination_config(%{"page_size" => "1000"}, 10)
  end

  test "invalid pages fall back to 1" do
    for page <- ["0", "-3", "abc", "", "1000001", String.duplicate("9", 40), ["1"], %{"a" => "1"}] do
      assert TransportWeb.PaginationHelpers.make_pagination_config(%{"page" => page}).page_number == 1
    end
  end
end
