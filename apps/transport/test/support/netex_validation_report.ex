defmodule NeTExValidationReportHelpers do
  @moduledoc """
  A set of helpers to test NeTEx validation reports.
  """

  import Phoenix.ConnTest

  def csv_response(conn, status) do
    body = response(conn, status)
    _ = response_content_type(conn, :csv)

    body
  end

  def parse_csv(body) do
    [body]
    |> CSV.decode!(headers: true)
    |> Enum.to_list()
  end

  def parquet_response(conn, status) do
    body = response(conn, status)
    _ = response_content_type(conn, :"vnd.apache.parquet")

    body
  end

  def parse_parquet(body) do
    body
    |> Explorer.DataFrame.load_parquet!()
    |> Explorer.DataFrame.to_rows()
  end
end
