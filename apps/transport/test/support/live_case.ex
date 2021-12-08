defmodule TransportWeb.LiveCase do
  @moduledoc """
  This module defines the test case to be used by
  tests interacting with LiveView.
  """
  use ExUnit.CaseTemplate

  using(_options) do
    quote do
      # Setting async: false for now because live tests
      # send Telemetry events stored in the database
      import Phoenix.ConnTest

      def extract_data_from_html(html) do
        doc = Floki.parse_document!(html)
        headers = doc |> Floki.find("table thead tr th") |> Enum.map(&Floki.text/1)
        row = doc |> Floki.find("table tbody tr td") |> Enum.map(&Floki.text/1)
        headers |> Enum.zip(row) |> Enum.into(%{})
      end

      def setup_admin_in_session(conn) do
        conn
        |> init_test_session(%{
          current_user: %{
            "organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]
          }
        })
      end
    end
  end
end
