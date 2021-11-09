defmodule GBFS.FeedView do
  use GBFS, :view

  def render("gbfs.json", %{data: data} = params) do
    ttl = Map.get(params, :ttl, 300)

    res = %{
      "last_updated" => Map.get(params, "last_updated", default_last_updated()),
      "ttl" => ttl,
      "data" => data
    }

    case Map.get(params, :version) do
      nil -> res
      v -> Map.put(res, "version", v)
    end
  end

  def render(_conn, %{data: data}) do
    data
  end

  defp default_last_updated, do: DateTime.utc_now() |> DateTime.to_unix()
end
