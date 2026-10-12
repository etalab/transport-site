defmodule TransportWeb.Backoffice.PageViewTest do
  use ExUnit.Case, async: true
  require Phoenix.LiveViewTest
  doctest TransportWeb.Backoffice.PageView, import: true

  test "sort_link" do
    conn = Phoenix.ConnTest.build_conn(:get, "/backoffice?q=bus") |> Plug.Conn.fetch_query_params()
    order_by = %{field: :custom_title, direction: :asc}

    html = sort_link(conn: conn, field: :custom_title, order_by: order_by)
    assert html =~ ~s(href="/backoffice?dir=desc&amp;order_by=custom_title&amp;q=bus#backoffice-datasets-table")
    assert html =~ ~s(Titre &lt;3 <i class="sort-icon fa fa-sort-down"></i>)

    html = sort_link(conn: conn, field: :end_date, order_by: order_by)
    assert html =~ ~s(href="/backoffice?dir=asc&amp;order_by=end_date&amp;q=bus#backoffice-datasets-table")
    assert html =~ ~s(<i class="sort-icon fa fa-sort"></i>)
  end

  defp sort_link(assigns) do
    assigns = Keyword.put(assigns, :inner_block, [%{inner_block: fn _, _ -> "Titre <3" end}])
    Phoenix.LiveViewTest.render_component(&TransportWeb.Backoffice.PageView.sort_link/1, assigns)
  end
end
