defmodule Unlock.DynamicIRVE.Controller do
  @moduledoc """
  Handles HTTP requests for `Unlock.Config.Item.DynamicIRVEAggregate` items.

  Query parameters (all optional):

    * `status=1` — exclusive: returns JSON status of all feeds. Ignores `format`
      and the data-shaping options below.
    * `format=csv` (default) or `format=parquet` — format of the aggregated data.
    * `include_origin=1` — adds an `origin` column (data formats only).
    * `limit_per_source=N` — caps rows per origin (data formats only).
  """

  import Plug.Conn

  alias Explorer.DataFrame
  alias Unlock.DynamicIRVE.{FeedStore, Renderer, Status}

  def serve(conn, %Unlock.Config.Item.DynamicIRVEAggregate{} = item) do
    conn = fetch_query_params(conn)

    if to_boolean(conn.query_params["status"]) do
      serve_status(conn, item)
    else
      serve_data(conn, item)
    end
  end

  defp serve_status(conn, item) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(Status.build(item)))
  end

  defp serve_data(conn, item) do
    case aggregate(item) do
      nil ->
        send_resp(conn, 503, "No data available yet")

      df ->
        format = parse_format(conn.query_params["format"])

        opts = [
          include_origin: to_boolean(conn.query_params["include_origin"]),
          limit_per_source: to_nil_or_integer(conn.query_params["limit_per_source"])
        ]

        {body, content_type, extension} = Renderer.render(df, format, opts)

        filename =
          "#{item.identifier}-#{DateTime.utc_now() |> DateTime.to_iso8601()}.#{extension}"

        conn
        |> put_resp_header("content-disposition", "attachment; filename=#{filename}")
        |> put_resp_content_type(content_type, charset(format))
        |> send_resp(200, body)
    end
  end

  # Concatenates all available feed DataFrames with an "origin" column (the slug).
  # Returns nil if no feed has data yet.
  defp aggregate(item) do
    dfs =
      item.feeds
      |> Enum.map(fn feed -> {feed.slug, FeedStore.get_feed(item.identifier, feed.slug)} end)
      |> Enum.flat_map(fn
        {slug, %{df: %DataFrame{} = df}} ->
          [DataFrame.put(df, "origin", List.duplicate(slug, DataFrame.n_rows(df)))]

        _ ->
          []
      end)

    case dfs do
      [] -> nil
      _ -> DataFrame.concat_rows(dfs)
    end
  end

  defp parse_format(nil), do: :csv
  defp parse_format("csv"), do: :csv
  defp parse_format("parquet"), do: :parquet

  defp charset(:csv), do: "utf-8"
  defp charset(:parquet), do: nil

  defp to_nil_or_integer(nil), do: nil
  defp to_nil_or_integer(data), do: String.to_integer(data)

  defp to_boolean(nil), do: false
  defp to_boolean("0"), do: false
  defp to_boolean("1"), do: true
end
