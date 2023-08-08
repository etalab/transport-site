defmodule Transport.DocumentationLinksTest do
  use ExUnit.Case, async: true
  @moduletag :documentation_links
  @documentation_domain "doc.transport.data.gouv.fr"

  test "documentation links are valid" do
    regexp = ~r/https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&\/\/=]*)/
    {output, 0} = System.shell("grep -r #{@documentation_domain} ../../apps/transport/lib")

    failures =
      regexp
      |> Regex.scan(output)
      |> Enum.filter(fn [url | _] -> String.contains?(url, @documentation_domain) end)
      |> Enum.map(fn [url | _] -> url |> URI.parse() |> Map.replace!(:fragment, nil) |> URI.to_string() end)
      |> Enum.uniq()
      |> Enum.map(fn url -> {HTTPoison.head(url), url} end)
      |> Enum.reject(fn {response, _} ->
        case response do
          {:ok, %HTTPoison.Response{status_code: status_code}} when status_code in [200, 302] -> true
          _ -> false
        end
      end)

    assert [] == failures, "Unexpected status codes for:\n#{Enum.map_join(failures, "\n", &elem(&1, 1))}"
  end
end
