defmodule GBFS.FeedView do
  use GBFS, :view

  def render("gbfs.json", %{data: data} = params) do
    %{
      "last_updated" => Map.get(params, "last_updated", default_last_updated()),
      "ttl" => 3600,
      "data" => data
    }
  end

  defp default_last_updated, do: DateTime.utc_now() |> DateTime.to_unix()

end
