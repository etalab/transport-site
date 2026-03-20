defmodule TransportWeb.PaginationHelpersTest do
  use TransportWeb.ConnCase, async: false
  import DB.Factory

  import TransportWeb.PaginationHelpers

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "pagination_links" do
    test "simple links" do
      assert test_pagination(1, %{}) == []
      assert test_pagination(1, %{"page" => "1"}) == []

      test_pagination(2, %{})
      |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])

      test_pagination(2, %{"page" => "1"})
      |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2"}, {">>", "/datasets?page=2"}])

      test_pagination(2, %{"page" => "2"})
      |> assert_has_pages([{"<<", "/datasets"}, {"1", "/datasets"}, {"2", nil}])
    end

    test "custom path" do
      opts = [path: &custom_path/3]

      test_pagination(2, %{}, opts)
      |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2#list"}, {">>", "/datasets?page=2#list"}])

      test_pagination(2, %{"page" => "1"}, opts)
      |> assert_has_pages([{"1", nil}, {"2", "/datasets?page=2#list"}, {">>", "/datasets?page=2#list"}])

      test_pagination(2, %{"page" => "2"}, opts)
      |> assert_has_pages([{"<<", "/datasets#list"}, {"1", "/datasets#list"}, {"2", nil}])
    end
  end

  defp custom_path(conn, action, params) do
    dataset_path(conn, action, params) <> "#list"
  end

  defp test_pagination(n_pages, params) do
    {conn, pagination} = setup_pagination(n_pages, params)

    conn
    |> pagination_links(pagination)
    |> Phoenix.HTML.safe_to_string()
    |> Floki.parse_document!()
  end

  defp test_pagination(n_pages, params, opts) do
    {conn, pagination} = setup_pagination(n_pages, params)

    conn
    |> pagination_links(pagination, opts)
    |> Phoenix.HTML.safe_to_string()
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

  defp setup_pagination(n_pages, params) do
    page_size = make_pagination_config(%{}).page_size

    conn = build_conn(:get, "/", params)

    datasets =
      for _n <- 1..(page_size * n_pages) do
        insert(:dataset)
      end

    pagination = Scrivener.paginate(datasets, make_pagination_config(params))

    {conn, pagination}
  end
end
