defmodule Unlock.DynamicIRVE.Controller do
  @moduledoc """
  Serves HTTP requests for `Unlock.Config.Item.DynamicIRVEAggregate` items.

  Query parameters (all optional):

    * `status=1` — exclusive: returns JSON status of all feeds. Ignores `format`
      and the data-shaping options below.
    * `format=csv` (default) or `format=parquet` — format of the aggregated data.
    * `include_origin=1` — adds an `origin` column (data formats only).
    * `limit_per_source=N` — caps rows per origin (data formats only).
  """

  import Plug.Conn
  import Unlock.Params, only: [to_boolean: 1, to_nil_or_integer: 1]

  alias Explorer.DataFrame
  alias Unlock.DynamicIRVE.FeedStore

  def serve(conn, %Unlock.Config.Item.DynamicIRVEAggregate{} = item) do
    conn = fetch_query_params(conn)

    if to_boolean(conn.query_params["status"]) do
      serve_status(conn, item)
    else
      serve_data(conn, item)
    end
  end

  defp serve_status(conn, item) do
    feeds = Enum.map(item.feeds, &feed_status(item.identifier, &1))
    payload = %{feeds: feeds, row_count: feeds |> Enum.map(& &1.row_count) |> Enum.sum()}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(payload))
  end

  defp feed_status(parent_id, feed) do
    data = FeedStore.get_feed(parent_id, feed.slug)
    data |> status_fields(feed.slug) |> Map.put(:row_count, row_count(data))
  end

  defp status_fields(nil, slug), do: %{slug: slug, status: "pending"}

  defp status_fields(%{error: nil, last_updated_at: t}, slug),
    do: %{slug: slug, status: "OK", last_updated_at: t}

  defp status_fields(%{error: e, last_errored_at: le, last_updated_at: lu}, slug),
    do: %{slug: slug, status: "KO", error: e, last_errored_at: le, last_updated_at: lu}

  defp row_count(%{df: %DataFrame{} = df}), do: DataFrame.n_rows(df)
  defp row_count(_), do: 0

  defp serve_data(conn, item), do: serve_data(conn, item, aggregate(item))

  defp serve_data(conn, _item, nil), do: send_resp(conn, 503, "No data available yet")

  defp serve_data(conn, item, df) do
    format = parse_format(conn.query_params["format"])
    include_origin = to_boolean(conn.query_params["include_origin"])
    limit_per_source = to_nil_or_integer(conn.query_params["limit_per_source"])

    {body, content_type, extension} =
      df
      |> apply_limit(limit_per_source)
      |> DataFrame.select(columns(include_origin))
      |> dump(format)

    filename = "#{item.identifier}-#{DateTime.utc_now() |> DateTime.to_iso8601()}.#{extension}"

    conn
    |> put_resp_header("content-disposition", "attachment; filename=#{filename}")
    |> put_resp_content_type(content_type, charset(format))
    |> send_resp(200, body)
  end

  # Concatenates all available feed DataFrames with an "origin" column (the slug).
  # Returns nil if no feed has data yet.
  defp aggregate(item) do
    item.feeds
    |> Enum.flat_map(&tagged_df(item.identifier, &1))
    |> concat()
  end

  defp tagged_df(parent_id, feed) do
    case FeedStore.get_feed(parent_id, feed.slug) do
      %{df: %DataFrame{} = df} ->
        [DataFrame.put(df, "origin", List.duplicate(feed.slug, DataFrame.n_rows(df)))]

      _ ->
        []
    end
  end

  defp concat([]), do: nil
  defp concat(dfs), do: DataFrame.concat_rows(dfs)

  defp apply_limit(df, nil), do: df

  defp apply_limit(df, n) when is_integer(n),
    do: df |> DataFrame.group_by("origin") |> DataFrame.head(n) |> DataFrame.ungroup()

  defp columns(false), do: Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
  defp columns(true), do: columns(false) ++ ["origin"]

  defp dump(df, :csv), do: {DataFrame.dump_csv!(df), "text/csv", "csv"}

  defp dump(df, :parquet),
    do: {DataFrame.dump_parquet!(df), "application/vnd.apache.parquet", "parquet"}

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
