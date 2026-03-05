defmodule TransportWeb.PaginationHelpersTest do
  use TransportWeb.ConnCase, async: false
  import DB.Factory

  import TransportWeb.PaginationHelpers

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "pagination_links" do
    test "simple links" do
      assert paginate(1, %{}) == ""
      assert paginate(1, %{"page" => "1"}) == ""

      assert paginate(2, %{}) ==
               "<nav><ul class=\"pagination\"><li class=\"active\"><a class=\"\">1</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2\" rel=\"next\">2</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2\" rel=\"next\">&gt;&gt;</a></li></ul></nav>"

      assert paginate(2, %{"page" => "1"}) ==
               "<nav><ul class=\"pagination\"><li class=\"active\"><a class=\"\">1</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2\" rel=\"next\">2</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2\" rel=\"next\">&gt;&gt;</a></li></ul></nav>"

      assert paginate(2, %{"page" => "2"}) ==
               "<nav><ul class=\"pagination\"><li class=\"\"><a class=\"\" href=\"/datasets\" rel=\"prev\">&lt;&lt;</a></li><li class=\"\"><a class=\"\" href=\"/datasets\" rel=\"prev\">1</a></li><li class=\"active\"><a class=\"\">2</a></li></ul></nav>"
    end

    test "custom path" do
      opts = [path: &custom_path/3]

      assert paginate(2, %{}, opts) ==
               "<nav><ul class=\"pagination\"><li class=\"active\"><a class=\"\">1</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2#list\" rel=\"next\">2</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2#list\" rel=\"next\">&gt;&gt;</a></li></ul></nav>"

      assert paginate(2, %{"page" => "1"}, opts) ==
               "<nav><ul class=\"pagination\"><li class=\"active\"><a class=\"\">1</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2#list\" rel=\"next\">2</a></li><li class=\"\"><a class=\"\" href=\"/datasets?page=2#list\" rel=\"next\">&gt;&gt;</a></li></ul></nav>"

      assert paginate(2, %{"page" => "2"}, opts) ==
               "<nav><ul class=\"pagination\"><li class=\"\"><a class=\"\" href=\"/datasets#list\" rel=\"prev\">&lt;&lt;</a></li><li class=\"\"><a class=\"\" href=\"/datasets#list\" rel=\"prev\">1</a></li><li class=\"active\"><a class=\"\">2</a></li></ul></nav>"
    end
  end

  defp custom_path(conn, action, params) do
    dataset_path(conn, action, params) <> "#list"
  end

  defp paginate(n_pages, params) do
    {conn, pagination} = setup_pagination(n_pages, params)

    conn
    |> pagination_links(pagination)
    |> Phoenix.HTML.safe_to_string()
  end

  defp paginate(n_pages, params, opts) do
    {conn, pagination} = setup_pagination(n_pages, params)

    conn
    |> pagination_links(pagination, opts)
    |> Phoenix.HTML.safe_to_string()
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
