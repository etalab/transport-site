Mix.install([
  {:req, "~> 0.3.0"},
  {:dotenvy, "~> 0.8.0"}
])

defmodule EnvConfig do
  def read!() do
    env_file = Path.join(__ENV__.file, "../../.env") |> Path.expand()
    Dotenvy.source!(env_file)
  end
end

# A simple example of HTTP pagination of an API, using tools provided by Elixir.
# We build "streams" which are lazy-evaluated enumerables.
defmodule NotionClient do
  def http_options(notion_secret) do
    [auth: {:bearer, notion_secret}, headers: [{"Notion-Version", "2022-06-28"}]]
  end

  def build_base_url(table_id), do: "https://api.notion.com/v1/databases/#{table_id}/query"

  # an example of creating a stream (lazy-evaluted) based on HTTP pagination via `Stream.resource/3`
  # https://hexdocs.pm/elixir/Stream.html#resource/3
  def database_items_via_stream_resource(table_id, notion_secret) do
    base_url = build_base_url(table_id)

    # function called by `Stream.resource`, until it returns {:halt, ...}
    next_fn = fn
      :done ->
        {:halt, nil}

      {url, start_cursor} ->
        # https://developers.notion.com/reference/pagination
        json = %{page_size: 100}
        json = if start_cursor, do: Map.put(json, :start_cursor, start_cursor), else: json
        options = http_options(notion_secret) |> Keyword.put(:json, json)

        %{status: 200, body: body} = Req.post!(url, options)
        acc = if cursor = body["next_cursor"], do: {url, cursor}, else: :done
        {body["results"], acc}
    end

    Stream.resource(
      # initially, start_cursor is not available
      fn -> {base_url, nil} end,
      next_fn,
      fn _ -> nil end
    )
  end

  # Since we have a simple case, we can even just use `Stream.unfold`
  # https://hexdocs.pm/elixir/Stream.html#unfold/2
  def database_items_via_stream_unfold(table_id, notion_secret) do
    base_url = build_base_url(table_id)

    req = fn
      nil ->
        nil

      {url, start_cursor} ->
        # https://developers.notion.com/reference/pagination
        json = %{page_size: 100}
        json = if start_cursor, do: Map.put(json, :start_cursor, start_cursor), else: json
        options = http_options(notion_secret) |> Keyword.put(:json, json)
        %{status: 200, body: body} = Req.post!(url, options)
        acc = if c = body["next_cursor"], do: {url, c}, else: nil
        {body["results"], acc}
    end

    Stream.unfold({base_url, nil}, req)
    # https://hexdocs.pm/elixir/Stream.html#flat_map/2 is needed
    |> Stream.flat_map(fn x -> x end)
  end
end

defmodule Mapper do
  def run(stream) do
    stream
    |> Stream.map(fn x -> x["properties"]["Nom"]["title"] |> List.first() |> Map.fetch!("plain_text") end)
    |> Stream.with_index()
    |> Stream.each(&IO.inspect(&1, IEx.inspect_opts()))
    |> Stream.run()
  end
end

%{
  "NOTION_SECRET" => notion_secret,
  "NOTION_ORGANIZATIONS_TABLE_ID" => notion_org_table_id
} = EnvConfig.read!()

IO.puts("========= database_items_via_stream_resource =========")

NotionClient.database_items_via_stream_resource(notion_org_table_id, notion_secret)
|> Stream.take(3)
|> Mapper.run()

IO.puts("========= database_items_via_stream_unfold =========")

NotionClient.database_items_via_stream_unfold(notion_org_table_id, notion_secret)
|> Stream.take(2)
|> Mapper.run()
