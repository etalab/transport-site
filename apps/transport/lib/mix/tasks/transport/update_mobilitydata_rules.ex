defmodule Mix.Tasks.Transport.UpdateMobilitydataRules do
  @moduledoc """
  Update the MobilityData GTFS Validator rules JSON from the latest release.

  Fetches `rules.json` from the latest GitHub release of the [GTFS Validator](https://github.com/MobilityData/gtfs-validator)
  and writes it to `priv/mobilitydata_gtfs_rules.json`, pretty-printed for readability.

  ## Examples

      mix transport.update_mobilitydata_rules
  """

  use Mix.Task

  @rules_path Path.join([__DIR__, "../../../../priv/mobilitydata_gtfs_rules.json"])
  @github_release_url "https://api.github.com/repos/MobilityData/gtfs-validator/releases/latest"
  @user_agent "transport-site-mix-task"

  def run(_) do
    Mix.Task.run("app.start")

    version = fetch_latest_version()
    rules_json = download_rules(version)

    File.write!(@rules_path, Jason.encode!(Jason.decode!(rules_json), pretty: true))

    size = File.stat!(@rules_path).size

    IO.puts("""
    ✓ Updated mobilitydata_gtfs_rules.json from v#{version}
      Rules count: #{rule_count()}
      File size:   #{div(size, 1024)} KB
    """)
  end

  defp fetch_latest_version do
    response = HTTPoison.get!(@github_release_url, [{"user-agent", @user_agent}], hackney: [follow_redirect: true])

    case response.status_code do
      200 ->
        tag = Jason.decode!(response.body)["tag_name"]

        case String.trim_leading(tag, "v") do
          "" -> Mix.raise("GitHub release has no version tag: #{inspect(tag)}")
          version -> version
        end

      status ->
        Mix.raise("GitHub API returned status #{status}: #{String.slice(response.body, 0..200)}")
    end
  end

  defp download_rules(version) do
    url = "https://github.com/MobilityData/gtfs-validator/releases/download/v#{version}/rules.json"

    response = HTTPoison.get!(url, [{"user-agent", @user_agent}], hackney: [follow_redirect: true])

    case response.status_code do
      200 -> response.body
      status -> Mix.raise("Failed to download rules.json from v#{version} (status #{status})")
    end
  end

  defp rule_count do
    with {:ok, content} <- File.read(@rules_path),
         {:ok, rules} <- Jason.decode(content) do
      Map.keys(rules) |> length()
    else
      _ -> "?"
    end
  end
end
