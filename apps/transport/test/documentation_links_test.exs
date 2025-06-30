defmodule Transport.DocumentationLinksTest do
  use ExUnit.Case, async: true
  @moduletag :ci_only_on_mondays
  @documentation_domain "doc.transport.data.gouv.fr"

  test "documentation links are valid" do
    urls = documentation_urls()

    refute Enum.empty?(urls), "We should find #{@documentation_domain} URLs in our codebase"

    failures =
      urls
      |> Enum.map(fn url ->
        case HTTPoison.head(url) do
          {:ok, %HTTPoison.Response{status_code: status_code}} when status_code in [200, 302, 307] -> :success
          response -> {:error, url, response}
        end
      end)
      |> Enum.reject(&(&1 == :success))

    message = """
    Unexpected HTTP responses for:
    - #{failures |> Enum.map_join("\n - ", fn {:error, url, _response} -> url end)}

    Debug:
    #{inspect(failures)}
    """

    assert Enum.empty?(failures), message
  end

  defp documentation_urls do
    regexp = ~r/https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_\+.~#?&\/\/=]*)/
    {output, 0} = System.shell("grep -r #{@documentation_domain} ../../apps/transport/lib")

    regexp
    |> Regex.scan(output)
    |> Enum.filter(fn [url | _] -> String.contains?(url, @documentation_domain) end)
    |> Enum.map(fn [url | _] -> url |> URI.parse() |> Map.replace!(:fragment, nil) |> URI.to_string() end)
    |> Enum.uniq()
  end
end
