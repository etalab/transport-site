defmodule Transport.IRVE.V3.FieldChecks do
  @moduledoc """
  Checks the fields of a vendored Table Schema, one check per `field:rule` code
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
  Checks an all-strings data frame against the schema fields: a list of `{code, boolean series}`, in schema order.
  Raises on any schema construct it does not know of, so that a schema change can't go unnoticed.
  """
  def run(%Explorer.DataFrame{} = df, %{"fields" => fields}) do
    for %{"name" => name} = field <- fields,
        {rule, check} <- field_checks(df[name], field),
        do: {"#{name}:#{rule}", check}
  end

  defp field_checks(values, %{"name" => name, "type" => type, "constraints" => constraints} = field) do
    unknown = field |> Map.keys() |> Enum.reject(&(&1 in @known_keys or String.starts_with?(&1, "x-")))
    if unknown != [], do: raise("Unknown keys for field #{name}: #{inspect(unknown)}")

    {required, constraints} = Map.pop!(constraints, "required")
    present = Primitives.has_value(values)

    type_checks =
      for {rule, valid?} <- type_rules(type, field["format"]), do: {rule, only_where(present, valid?.(values))}

    typed = Enum.reduce(type_checks, present, fn {_rule, check}, gate -> Series.and(gate, check) end)

    constraint_checks =
      for {key, value} <- Enum.sort(constraints),
          key not in @table_level_constraints,
          do: {key, only_where(typed, constraint_valid?(key, value, values))}

    if(required, do: [{"required", present}], else: []) ++ type_checks ++ constraint_checks
  end

  defp type_rules("string", nil), do: []
  defp type_rules("string", "email"), do: [{"format", &Primitives.email?/1}]
  defp type_rules("integer", nil), do: [{"type", &Primitives.integer_value?/1}]
  defp type_rules("number", nil), do: [{"type", &Primitives.numeric?/1}]
  defp type_rules("boolean", nil), do: [{"type", &Primitives.boolean_value?/1}]
  defp type_rules("date", fmt), do: [{"type", &Primitives.date?(&1, fmt)}]
  defp type_rules("datetime", fmt), do: [{"type", &V3.datetime?(&1, fmt)}]
  defp type_rules(type, nil) when type in ["array", "object"], do: []

  defp constraint_valid?("pattern", pattern, values), do: V3.full_match(values, pattern)
  defp constraint_valid?("enum", allowed, values), do: Primitives.is_in_enum(values, allowed)
  defp constraint_valid?("minimum", min, values), do: Primitives.is_greater_or_equal(values, min)
  defp constraint_valid?("maximum", max, values), do: V3.is_less_or_equal(values, max)

  # `nil` (not evaluated) where `gate` does not hold.
  defp only_where(gate, check), do: Series.select(gate, check, Series.from_list([nil], dtype: :boolean))
end
