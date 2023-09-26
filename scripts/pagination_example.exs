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

defmodule NotionClient do
  def notion_headers(notion_secret) do
    [auth: {:bearer, notion_secret}, headers: [{"Notion-Version", "2022-06-28"}]]
  end

  def database_items(table_id, notion_secret) do
    base_url = "https://api.notion.com/v1/databases/#{table_id}/query"

    next_fn = fn acc ->
      if acc == :done do
        {:halt, nil}
      else
        {url, start_cursor} = acc
        # https://developers.notion.com/reference/pagination
        json = %{
          page_size: 100
        }
        json = if start_cursor, do: Map.put(json, :start_cursor, start_cursor), else: json
        options = notion_headers(notion_secret) |> Keyword.put(:json, json)

        %{status: 200, body: body} = Req.post!(url, options)
        acc = if body["next_cursor"], do: {url, body["next_cursor"]}, else: :done
        {body["results"], acc}
      end
    end

    Stream.resource(
      # initially, start_cursor is not available
      fn -> {base_url, nil} end,
      next_fn,
      fn _ -> nil end
    )
  end
end

%{
  "NOTION_SECRET" => notion_secret,
  "NOTION_ORGANIZATIONS_TABLE_ID" => notion_org_table_id
} = EnvConfig.read!()

organizations = NotionClient.database_items(notion_org_table_id, notion_secret)

organizations
#|> Stream.take(2)
|> Stream.map(fn x -> x["properties"]["Nom"]["title"] |> List.first() |> Map.fetch!("plain_text") end)
|> Stream.with_index()
|> Stream.each(&IO.inspect(&1, IEx.inspect_opts))
|> Stream.run()
