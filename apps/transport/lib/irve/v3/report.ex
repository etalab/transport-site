defmodule Transport.IRVE.V3.Report do
  @moduledoc """
  Result of an IRVE v3 validation: one entry per validated file (`:statique`, `:dynamique`, `:tarifs`), with

  - `sha256`, `schema` (version) and `n_rows` of the file;
  - `file_errors`: if any, the rows were not checked and `checks` is `nil`;
  - `checks`: a data frame with one boolean column per `field:rule` code, row i being the i-th row of the file
    (`true` passes, `false` fails, `nil` not evaluated). It holds no copy of the data: the checksum allows
    going back to the file for samples.

  Written as `manifest.json` (everything but the checks, plus counts per code) and one Parquet file per input.
  Booleans with nils are stored as bits in Parquet, and compress to almost nothing when uniform.
  """

  alias Explorer.{DataFrame, Series}

  @enforce_keys [:files]
  defstruct [:files]

  def valid?(%__MODULE__{files: files}) do
    Enum.all?(files, fn {_role, file} ->
      file.file_errors == [] and Enum.all?(counts(file.checks), fn {_code, count} -> count.errors == 0 end)
    end)
  end

  @doc """
  Errors and not evaluated rows, for every code (codes without errors included, to keep the report exhaustive).
  """
  def counts(nil), do: %{}

  def counts(%DataFrame{} = checks) do
    Map.new(DataFrame.names(checks), fn code ->
      {code, %{errors: checks[code] |> Series.not() |> Series.sum(), not_evaluated: Series.nil_count(checks[code])}}
    end)
  end

  def manifest(%__MODULE__{files: files}) do
    %{
      files:
        Map.new(files, fn {role, file} ->
          {role, file |> Map.take([:sha256, :schema, :n_rows, :file_errors]) |> Map.put(:counts, counts(file.checks))}
        end)
    }
  end

  def write!(%__MODULE__{files: files} = report, dir) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "manifest.json"), report |> manifest() |> Jason.encode!(pretty: true))

    for {role, %{checks: %DataFrame{} = checks}} <- files,
        do: DataFrame.to_parquet!(checks, Path.join(dir, "#{role}.parquet"), compression: :zstd)

    :ok
  end
end
