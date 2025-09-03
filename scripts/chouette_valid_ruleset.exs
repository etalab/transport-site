defmodule Script do
  @moduledoc """
  Script to debug and inspect current implementation of validation rules for the
  French NeTEx profile.
  """

  import Transport.NeTEx.FrenchProfile

  def document_rulesets do
    with_file("chouette_ruleset.json", &ruleset/1)
    with_file("chouette_ruleset.md", &markdown/1)
  end

  def publish_rulesets do
    result =
      with_string(&ruleset/1)
      |> client().post_ruleset("French profile", "pan:french_profile:1")

    case result do
      :ok -> IO.puts("Rulesets properly pushed")
      {:error, msg} -> IO.puts("Error pushing the rulesets: #{msg}")
    end
  end

  defp client do
    Transport.EnRouteChouetteValidRulesetsClient.Wrapper.impl()
  end

  defp with_file(file, proc), do: File.write(file, with_string(proc))

  defp with_string(proc) do
    {:ok, device} = StringIO.open("")

    proc.(device)

    StringIO.flush(device)
  end
end

Script.document_rulesets()
Script.publish_rulesets()
