defmodule Checker do
  @doc """
  ### required

  iex> Checker.check_constraint("", "required", true)
  false
  iex> Checker.check_constraint("  ", "required", true)
  false
  iex> Checker.check_constraint(" something", "required", true)
  true
  """

  def check_constraint(value, "required", true) when is_binary(value) do
    value
    |> String.trim() != ""
  end

  def check_constraint(value, "pattern", pattern) do
    # Runtime for now (more costly), may move to compile time.
    pattern
    |> Regex.compile!()
    |> Regex.match?(value)
  end

  def check_constraint(value, "enum", allowed_values) do
    value in allowed_values
  end

  def check_type(value, "string") do
    is_binary(value)
  end

  # def check_type(value, "datetime") do
  #   DateTime.from_iso8601(value)
  #   |> match?({:ok, _, _})
  # end
end
