defmodule Script do
  @moduledoc """
  Script to debug and inspect current implementation of validation rules for the
  French NeTEx profile.
  """

  import Transport.NeTEx.FrenchProfile
  alias Transport.EnRoute.ChouetteValidRulesetsClient.Slugs
  alias Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper

  def document_rulesets do
    with_file("chouette_ruleset.json", &ruleset/1)
    with_file("chouette_ruleset.md", &markdown/1)
  end

  def list_rulesets do
    Wrapper.impl().list_rulesets()
    |> IO.inspect()
  end

  def purge_rulesets do
    Wrapper.impl().list_rulesets()
    |> Enum.each(fn %{"id" => ruleset_id, "slug" => slug} ->
      IO.puts("Deleting profile #{slug}")
      Wrapper.impl().delete_ruleset(ruleset_id)
    end)
  end

  def list_versions(slug) do
    Wrapper.list_versions(slug)
    |> Enum.map(fn %{"slug" => version_slug, "id" => id, "updated_at" => timestamp} ->
      {version_slug, id, timestamp}
    end)
    |> IO.inspect()
  end

  def find_ruleset_id(slug) do
    Wrapper.find_ruleset_id(slug)
    |> IO.inspect(label: "found slug #{slug}")
  end

  def get_ruleset(slug) do
    Wrapper.impl().get_ruleset(slug)
    |> IO.inspect()
  end

  def publish_rulesets(slug) do
    slug = Slugs.check_slug!(slug)

    result =
      with_string(&ruleset/1)
      |> prepend_enroute_starter_kit()
      |> upsert_ruleset("French profile", slug)

    case result do
      {:ok, ruleset_id} -> IO.puts("Ruleset properly pushed with id: #{ruleset_id}")
      {:error, msg} -> IO.puts("Error pushing the rulesets: #{msg}")
    end
  end

  def upsert_ruleset(ruleset, name, slug) do
    case Wrapper.impl().create_ruleset(ruleset, name, slug) do
      {:error, "Slug already taken"} -> Wrapper.impl().update_ruleset(ruleset, name, slug)
      result -> result
    end
  end

  defp with_file(file, proc), do: File.write(file, with_string(proc))

  defp with_string(proc) do
    {:ok, device} = StringIO.open("")

    proc.(device)

    StringIO.flush(device)
  end

  # I wish we could refer another ruleset
  defp prepend_enroute_starter_kit(json) do
    enroute_rules = read_enroute_starter_kit()
    pan_rules = Jason.decode!(json)

    Jason.encode!(enroute_rules ++ pan_rules)
  end

  defp read_enroute_starter_kit do
    "apps/transport/lib/netex/enroute-starter-kit.json"
    |> File.read!()
    |> Jason.decode!()
  end
end

# Script.document_rulesets()

# Script.list_rulesets()
# Script.purge_rulesets()
# Script.list_rulesets()
# Script.find_ruleset_id("pan:french_profile:2")
# Script.find_ruleset_id("pan:french_profile:7")

# Script.get_ruleset("pan:french_profile:7")
Script.publish_rulesets("pan:french_profile:1")
Script.get_ruleset("pan:french_profile:1")

Script.list_versions("pan:french_profile")
