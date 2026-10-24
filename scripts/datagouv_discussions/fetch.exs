# Fetches the data.gouv.fr discussions of every dataset listed on transport.data.gouv.fr (public APIs only),
# tagging each comment with a role: "producer", "pan" or "other".
#
# Usage: elixir scripts/datagouv_discussions/fetch.exs <out.json>
#
# Caveats: the PAN API does not list archived/hidden datasets, and the data.gouv.fr API only exposes
# *current* organization members (former members or contractors of a producer show up as "other").
Mix.install([:req], lockfile: Path.join(__DIR__, "../../mix.lock"))

defmodule DatagouvDiscussions do
  @pan_org_id "5abca8d588ee386ee6ece479"

  def fetch_all do
    datasets = pan_datasets()
    members = current_members([@pan_org_id | Enum.map(datasets, & &1["publisher"]["id"])])

    datasets
    |> pmap(fn dataset -> Enum.map(discussions(dataset["datagouv_id"]), &tag(&1, dataset, members)) end)
    |> Enum.concat()
    |> Enum.sort_by(&{&1["created"], &1["id"]})
  end

  def pan_datasets, do: get("https://transport.data.gouv.fr/api/datasets")

  def current_members(org_ids) do
    org_ids
    |> Enum.uniq()
    |> pmap(fn id ->
      {id, for(m <- get("https://www.data.gouv.fr/api/1/organizations/#{id}/")["members"], do: m["user"]["id"])}
    end)
    |> Map.new()
  end

  def discussions(datagouv_id),
    do: all_pages("https://www.data.gouv.fr/api/1/discussions/?for=#{datagouv_id}&page_size=100")

  def role(comment, publisher_id, members) do
    cond do
      posted_by?(comment, publisher_id, members) -> "producer"
      posted_by?(comment, @pan_org_id, members) -> "pan"
      true -> "other"
    end
  end

  defp posted_by?(comment, org_id, members),
    do:
      get_in(comment, ["posted_by_organization", "id"]) == org_id or
        get_in(comment, ["posted_by", "id"]) in members[org_id]

  defp tag(discussion, dataset, members) do
    comments = for c <- discussion["discussion"], do: Map.put(c, "role", role(c, dataset["publisher"]["id"], members))

    Map.merge(discussion, %{
      "discussion" => comments,
      "dataset" => Map.take(dataset, ~w(datagouv_id slug title type publisher))
    })
  end

  defp all_pages(url) do
    url
    |> Stream.unfold(fn
      nil -> nil
      url -> (page = get(url)) && {page["data"], page["next_page"]}
    end)
    |> Enum.concat()
  end

  defp get(url), do: Req.get!(url).body

  # Higher concurrency got the client IP blocked by data.gouv.fr (TLS connection reset)
  defp pmap(enum, fun),
    do: enum |> Task.async_stream(fun, max_concurrency: 2, timeout: :infinity) |> Enum.map(fn {:ok, r} -> r end)
end

[out_path] = System.argv()
fetched_at = DateTime.utc_now()
discussions = DatagouvDiscussions.fetch_all()
# String keys: atom-keyed map iteration order depends on atom creation order, hence varies between runs
File.write!(out_path, JSON.encode!(%{"fetched_at" => fetched_at, "discussions" => discussions}))
IO.puts("discussions=#{length(discussions)} fetched_at=#{fetched_at}")
