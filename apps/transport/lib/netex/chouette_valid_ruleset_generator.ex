defmodule Transport.NeTEx.ChouetteValidRulesetGenerator do
  @moduledoc """
  Utilities to define ruleset for Chouette Valid API.

  Ruleset are first defined in an abstract manner and later encoded to the
  relevant syntax. Having an intermediary abstract representation provides
  following benefits:
  - intent is a bit more clear (the Chouette Valid encoding is too close to the XML bits)
  - it can keep track of source documentation for each rule to help maintain a user friendly interface
  """

  def mandatory_attributes(parent, names, documentation_title, documentation_url) do
    %{
      type: :mandatory_attributes,
      parent: parent,
      names: names,
      documentation_link: %{title: documentation_title, url: documentation_url}
    }
  end

  def encode_ruleset(definition, device \\ :stdio) do
    json =
      definition
      |> Enum.flat_map(&process_sub_profile/1)
      |> JSON.encode!()

    IO.puts(device, json)
  end

  def process_sub_profile(%{sub_profile: sub_profile, ruleset: ruleset}) do
    Enum.map(ruleset, &process_rule_context(sub_profile, &1))
  end

  def document_ruleset(ruleset, device \\ :stdio) do
    Enum.each(ruleset, &document_sub_profile(&1, device))
  end

  def document_sub_profile(%{title: title, ruleset: ruleset}, device) do
    IO.puts(device, "## #{title}")
    IO.puts(device, "")

    ruleset
    |> Enum.each(fn rule_context ->
      IO.puts(device, "In [#{rule_context.documentation_link.title}](#{rule_context.documentation_link.url}):")
      IO.puts(device, "")

      for name <- rule_context.names do
        IO.puts(device, "- `//#{rule_context.parent}/#{name}` : `0:1` -> `1:1`")
      end

      IO.puts(device, "")
    end)
  end

  def process_rule_context(sub_profile, %{type: :mandatory_attributes, parent: parent, names: names}) do
    %{
      rule_context: "resource/kind_of",
      resource_class: parent,
      rules: Enum.map(names, fn name -> process_mandatory_attribute_rule(sub_profile, parent, name) end)
    }
  end

  def process_mandatory_attribute_rule(sub_profile, parent, name) do
    %{
      rule: "attribute/mandatory",
      name: snake_case(name),
      criticity: "error",
      code: "pan:french_profile:#{sub_profile}:cardinalities:#{parent}:#{name}",
      message: "#{parent}/#{name} is mandatory"
    }
  end

  @doc """
  Convert to snake case as it's what's expected by Chouette Valid for some reason.

  iex> snake_case("Name")
  "name"

  iex> snake_case("LongName")
  "long_name"

  iex> snake_case("shortName")
  "short_name"
  """
  def snake_case(string) when is_binary(string) do
    IO.iodata_to_binary(snake_case_ascii(string, true))
  end

  def snake_case(string), do: string

  defp snake_case_ascii(<<char, rest::bits>>, true) when char >= ?A and char <= ?Z do
    [char + 32 | snake_case_ascii(rest, false)]
  end

  defp snake_case_ascii(<<char, rest::bits>>, false) when char >= ?A and char <= ?Z do
    [?_, char + 32 | snake_case_ascii(rest, false)]
  end

  defp snake_case_ascii(<<char, rest::bits>>, _), do: [char | snake_case_ascii(rest, false)]
  defp snake_case_ascii(<<>>, _), do: []
end
