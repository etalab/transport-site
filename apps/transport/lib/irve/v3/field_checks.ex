defmodule Transport.IRVE.V3.FieldChecks do
  @moduledoc """
  Compiles the fields of a vendored Table Schema into checks, one per `field:rule` code
  (e.g. `nb_pdc:required`, `nb_pdc:type`, `nb_pdc:minimum`).

  Each check gives a boolean series aligned on the rows: `true` passes, `false` fails, `nil` was not evaluated.
  An error is reported once: the type (or format) is only checked on present values, the constraints only
  on values of the right type.

  Array and object fields only get `required` here, their content being JSON. `unique` is a table-level check.
  """

  alias Explorer.Series
  alias Transport.DataFrame.Validation.Primitives
  alias Transport.IRVE.V3.Primitives, as: V3

  @known_keys ~w(name type format constraints arrayItem description example)
  @table_level_constraints ~w(unique)

  @doc """
  Turns each schema field into `{name, required?, type rule, constraint rules}`, a rule being `{rule, predicate}`.
  Raises on any schema construct it does not know of, so that a schema change can't go unnoticed.
  """
  def compile(%{"fields" => fields}), do: Enum.map(fields, &compile_field/1)

  defp compile_field(%{"name" => name, "type" => type, "constraints" => constraints} = field) do
    unknown = field |> Map.keys() |> Enum.reject(&(&1 in @known_keys or String.starts_with?(&1, "x-")))
    if unknown != [], do: raise("Unknown keys for field #{name}: #{inspect(unknown)}")

    {required, constraints} = Map.pop!(constraints, "required")
    constraint_rules = constraints |> Map.drop(@table_level_constraints) |> Enum.sort() |> Enum.map(&constraint_rule/1)

    {name, required, type_rule(type, field["format"]), constraint_rules}
  end

  defp type_rule("string", nil), do: nil
  defp type_rule("string", "email"), do: {"format", &Primitives.email?/1}
  defp type_rule("integer", nil), do: {"type", &Primitives.integer_value?/1}
  defp type_rule("number", nil), do: {"type", &Primitives.numeric?/1}
  defp type_rule("boolean", nil), do: {"type", &Primitives.boolean_value?/1}
  defp type_rule("date", fmt), do: {"type", &Primitives.date?(&1, fmt)}
  defp type_rule("datetime", fmt), do: {"type", &V3.datetime?(&1, fmt)}
  defp type_rule(type, nil) when type in ["array", "object"], do: nil

  defp constraint_rule({"pattern", pattern}), do: {"pattern", &V3.full_match(&1, pattern)}
  defp constraint_rule({"enum", values}), do: {"enum", &Primitives.is_in_enum(&1, values)}
  defp constraint_rule({"minimum", min}), do: {"minimum", &Primitives.is_greater_or_equal(&1, min)}
  defp constraint_rule({"maximum", max}), do: {"maximum", &V3.is_less_or_equal(&1, max)}

  @doc """
  Runs the compiled checks on an all-strings data frame: a list of `{code, boolean series}`, in schema order.
  """
  def run(%Explorer.DataFrame{} = df, compiled) do
    Enum.flat_map(compiled, fn {name, required, type_rule, constraint_rules} ->
      values = df[name]
      present = Primitives.has_value(values)
      {typed, type_check} = gated(values, present, type_rule)
      constraint_checks = Enum.map(constraint_rules, &elem(gated(values, typed, &1), 1))

      checks = [if(required, do: {"required", present}), type_check | constraint_checks]
      for {rule, series} <- Enum.reject(checks, &is_nil/1), do: {"#{name}:#{rule}", series}
    end)
  end

  # Evaluates the rule where `gate` holds: gives the gate for the next rules, and the check.
  defp gated(_values, gate, nil), do: {gate, nil}

  defp gated(values, gate, {rule, predicate}) do
    passed = predicate.(values)
    not_evaluated = Series.from_list([nil], dtype: :boolean)
    {Series.and(gate, passed), {rule, Series.select(gate, passed, not_evaluated)}}
  end
end
