defmodule TransportWeb.Components.PaginationTest do
  use ExUnit.Case, async: true
  require Phoenix.LiveViewTest

  test "nothing for a single page" do
    assert test_pagination(1, %{}) == []
    assert test_pagination(1, %{"page" => "1"}) == []
  end

  test "simple links" do
    test_pagination(2, %{})
    |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])

    test_pagination(2, %{"page" => "1"})
    |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])

    test_pagination(2, %{"page" => "2"})
    |> assert_has_pages([{"<<", "/datasets"}, {"1", "/datasets"}, {"2", nil}])

    test_pagination(5, %{"format" => "NeTEx", "page" => "3"})
    |> assert_has_pages([
      {"<<", "/datasets?format=NeTEx&page=2"},
      {"1", "/datasets?format=NeTEx"},
      {"2", "/datasets?format=NeTEx&page=2"},
      {"3", nil},
      {"4", "/datasets?format=NeTEx&page=4"},
      {"5", "/datasets?format=NeTEx&page=5"},
      {">>", "/datasets?format=NeTEx&page=4"}
    ])
  end

  test "anchor" do
    opts = [anchor: "list"]

    test_pagination(2, %{}, opts)
    |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2#list"}, {">>", "/datasets?page=2#list"}])

    test_pagination(2, %{"page" => "2"}, opts)
    |> assert_has_pages([{"<<", "/datasets#list"}, {"1", "/datasets#list"}, {"2", nil}])
  end

  test "params override query params, nil removes them" do
    test_pagination(2, %{"issue_type" => "A", "token" => "secret"}, params: [issue_type: "B"])
    |> assert_has_pages([
      {"1", nil},
      {"2", "/datasets?issue_type=B&token=secret&page=2"},
      {">>", "/datasets?issue_type=B&token=secret&page=2"}
    ])

    test_pagination(2, %{"issue_type" => "A"}, params: [issue_type: nil])
    |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])
  end

  test "empty q is dropped" do
    test_pagination(2, %{"q" => ""})
    |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])
  end

  test "ellipsis around the current window" do
    labels = test_pagination(20, %{"page" => "10"}) |> Floki.find("li") |> Enum.map(&Floki.text/1)

    assert labels == ["<<", "1", "…"] ++ Enum.map(5..15, &to_string/1) ++ ["…", "20", ">>"]
  end

  test "links stay on this site when the path starts with //" do
    conn =
      %{Phoenix.ConnTest.build_conn(:get, "/datasets") | request_path: "//datasets"} |> Plug.Conn.fetch_query_params()

    page = %Scrivener.Page{entries: [], page_number: 1, page_size: 20, total_entries: 40, total_pages: 2}

    Phoenix.LiveViewTest.render_component(&TransportWeb.Components.Pagination.pagination/1, conn: conn, page: page)
    |> Floki.parse_document!()
    |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])
  end

  test "markup" do
    doc = test_pagination(3, %{"page" => "2"})

    assert [{"nav", [{"aria-label", "Page navigation"}], _}] = doc
    assert doc |> Floki.find("ul.pagination li a") |> length() == 5
    assert doc |> Floki.find("li.active") |> Floki.text() == "2"
    assert doc |> Floki.find("a[rel=prev]") |> Enum.map(&Floki.text/1) == ["<<", "1"]
    assert doc |> Floki.find("a[rel=next]") |> Enum.map(&Floki.text/1) == ["3", ">>"]
  end

  defp test_pagination(total_pages, params, opts \\ []) do
    conn = Phoenix.ConnTest.build_conn(:get, "/datasets", params) |> Plug.Conn.fetch_query_params()

    page = %Scrivener.Page{
      entries: [],
      page_number: TransportWeb.PaginationHelpers.make_pagination_config(params).page_number,
      page_size: 20,
      total_entries: total_pages * 20,
      total_pages: total_pages
    }

    Phoenix.LiveViewTest.render_component(
      &TransportWeb.Components.Pagination.pagination/1,
      [conn: conn, page: page] ++ opts
    )
    |> Floki.parse_document!()
  end

  defp assert_has_pages(doc, links) do
    assert links == doc |> Floki.find("a") |> Enum.map(&extract_link/1)

    doc
  end

  defp extract_link(link) do
    href =
      case Floki.attribute(link, "href") do
        [href] -> href
        _ -> nil
      end

    {Floki.text(link), href}
  end
end
