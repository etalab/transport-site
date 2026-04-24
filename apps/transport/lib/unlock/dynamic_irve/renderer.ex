defmodule Unlock.DynamicIRVE.Renderer do
  @moduledoc """
  Serializes an aggregated dynamic IRVE DataFrame to a binary payload.

  Pure functions: given a DataFrame and options, returns a `{body, content_type, extension}`
  triplet. Slicing (`limit_per_source`) and column projection (`include_origin`) live here,
  so the controller stays free of DataFrame-level concerns.
  """

  alias Explorer.DataFrame

  @type format :: :csv | :parquet
  @type opts :: [include_origin: boolean(), limit_per_source: pos_integer() | nil]

  @spec render(DataFrame.t(), format, opts) :: {binary(), String.t(), String.t()}
  def render(%DataFrame{} = df, format, opts \\ []) do
    df
    |> apply_limit_per_source(Keyword.get(opts, :limit_per_source))
    |> DataFrame.select(columns(Keyword.get(opts, :include_origin, false)))
    |> dump(format)
  end

  defp apply_limit_per_source(df, nil), do: df

  defp apply_limit_per_source(df, n) when is_integer(n) do
    df
    |> DataFrame.group_by("origin")
    |> DataFrame.head(n)
    |> DataFrame.ungroup()
  end

  defp columns(false), do: schema_fields()
  defp columns(true), do: schema_fields() ++ ["origin"]

  defp schema_fields, do: Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()

  defp dump(df, :csv), do: {DataFrame.dump_csv!(df), "text/csv", "csv"}
  defp dump(df, :parquet), do: {DataFrame.dump_parquet!(df), "application/vnd.apache.parquet", "parquet"}
end
