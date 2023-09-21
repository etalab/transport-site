Mix.install([
  {:req, "~> 0.3.0"},
  {:dotenvy, "~> 0.8.0"}
])

defmodule NotionClient do
  import Dotenvy
  source!([".env", System.get_env()])

  @org_id_column_name "organisation_id_text"
  @reference_column_name "organisation"

  def notion_headers,
    do: [auth: {:bearer, env!("NOTION_SECRET")}, headers: [{"Notion-Version", "2022-06-28"}]]

  def get_notion_page_content(page_id) do
    Req.get!("https://api.notion.com/v1/blocks/#{page_id}/children", notion_headers())
  end

  def get_notion_database_content(database_id, start_cursor: start_cursor) do
    Process.sleep(350)
    Req.post!(
      "https://api.notion.com/v1/databases/#{database_id}/query",
      [json: %{"start_cursor" => start_cursor}] ++ notion_headers()
    )
  end

  def get_notion_database_content(database_id) do
    Process.sleep(350)
    Req.post!("https://api.notion.com/v1/databases/#{database_id}/query", notion_headers())
  end

  def results_content_follow_pagination(database_id) do
    %{status: 200, body: body} = NotionClient.get_notion_database_content(database_id)
    results_content_follow_pagination(database_id, body["next_cursor"], body["results"])
  end

  def results_content_follow_pagination(_database_id, nil, acc) do
    acc
  end

  def results_content_follow_pagination(database_id, next_cursor, acc) do
    %{status: 200, body: body} = NotionClient.get_notion_database_content(database_id, start_cursor: next_cursor)
    results_content_follow_pagination(database_id, body["next_cursor"], acc ++ body["results"])
  end



  def list_of_tuples_text_ref_real_id(results) do
    results
    |> Enum.map(fn line ->
      property = line |> get_in(["properties", @org_id_column_name])
      org_text_id = case property["type"] do
        "rich_text" -> property |> get_in(["rich_text"]) |> hd |> get_in(["plain_text"])
        "number" -> property |> get_in(["number"])
      end

      {org_text_id, line["id"]}
    end)
  end

  def patch_organisation_relation_property(entry_id, organisation_id) do
    Process.sleep(500)
    Req.patch!(
      "https://api.notion.com/v1/pages/#{entry_id}",
      [
        json: %{
          "properties" => %{
            @reference_column_name => %{"relation" => [%{"id" => organisation_id}]}
          }
        }
      ] ++ notion_headers()
    )
  end

  def link_organisations_to_contacts(organisation_database_id, contact_database_id) do
    # 1.Get the organisation database from Notion API, then transform it to get a map with their ID and slug
    IO.puts"Getting organisations..."
    map_of_orgs_ids = NotionClient.results_content_follow_pagination(organisation_database_id)
    |> NotionClient.list_of_tuples_text_ref_real_id()
    |> Map.new()

    IO.inspect(map_of_orgs_ids)

    # 2. Get the contact database from Notion API, then transform it to get a list of tuples
    IO.puts"Getting contacts..."
    list_of_tuples_of_contacts = NotionClient.results_content_follow_pagination(contact_database_id) |> NotionClient.list_of_tuples_text_ref_real_id()
    IO.inspect(map_of_orgs_ids)

    # 3. For each contact, patch it with the organisation ID
    IO.puts"Linking contacts to organisations..."
    list_of_tuples_of_contacts
    |> Enum.each(fn {org_text_id, contact_id} ->
      IO.puts("Linking #{contact_id} to #{org_text_id}")
      case Map.get(map_of_orgs_ids, org_text_id) do
        nil -> IO.puts("No organisation ref #{org_text_id} found for #{contact_id}")
        org_id -> NotionClient.patch_organisation_relation_property(contact_id, org_id)
      end
    end)
  end
end

organisation_database_id = "fill-me"
contact_database_id = "fill-me"

NotionClient.link_organisations_to_contacts(organisation_database_id, contact_database_id)
