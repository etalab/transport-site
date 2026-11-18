defmodule Transport.IRVE.V3.FixtureHelpers do
  @moduledoc """
  Helpers shared by the IRVE v3 fixture generators (static, dynamic, tarifs).
  """

  @doc """
  Runs `fun` with `:rand` seeded with `seed`, in a dedicated process: the same seed always gives the same
  result, and the caller's random state is left untouched.
  """
  def seeded(seed, fun) do
    Task.async(fn ->
      :rand.seed(:exsss, seed)
      fun.()
    end)
    |> Task.await(:infinity)
  end

  @doc """
  Field names of a vendored schema, in schema order.
  """
  def field_names(schema_file) do
    Transport.CachedFiles.read_json(schema_file)
    |> Map.fetch!("fields")
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  @doc """
  Serializes rows to CSV, columns in `fields` order, lists and objects as JSON.
  """
  def to_csv(rows, fields) do
    lines = Enum.map(rows, fn row -> Enum.map(fields, &format_value(Map.fetch!(row, &1))) end)
    [fields | lines] |> NimbleCSV.RFC4180.dump_to_iodata() |> IO.iodata_to_binary()
  end

  defp format_value(nil), do: ""
  defp format_value(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp format_value(%Date{} = value), do: Date.to_iso8601(value)
  defp format_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_value(value) when is_list(value) or is_map(value), do: Jason.encode!(value)
  defp format_value(value), do: to_string(value)
end
