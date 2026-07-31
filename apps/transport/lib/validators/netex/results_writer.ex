defmodule Transport.Validators.NeTEx.ResultsWriter do
  @moduledoc """
  Interface and resolver for write-side result adapters: helpers designed to
  serialize NeTEx validation results to the database.

  Each version module implements this behaviour with its own serialization logic.
  Call sites resolve the appropriate version via `resolve/1` (mirroring
  `ResultsReader.resolve/1`).

  For the active validator version, call sites use the resolved writer directly:

      writer = ResultsWriter.resolve(validator_version())
      df     = writer.to_dataframe(errors)
      binary = writer.to_binary_result(errors)
      digest = writer.digest(df)

  When writing results for a historical version (e.g. displaying a past report),
  `digest/2` accepts an explicit version so the summary format matches that
  version's template.
  """

  @callback to_dataframe(list()) :: Explorer.DataFrame.t()
  @callback to_binary_result(list()) :: binary()
  @callback digest(Explorer.DataFrame.t()) :: map()
  @callback count_max_severity(Explorer.DataFrame.t()) :: map()
  @callback get_max_severity_error(Explorer.DataFrame.t()) :: binary()

  def resolve("0.2.2"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_2
  def resolve("0.2.1"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_1
  def resolve("0.2.0"), do: Transport.Validators.NeTEx.ResultsAdapters.V0_2_0
  def resolve(_), do: Transport.Validators.NeTEx.ResultsAdapters.V0_1_0
end
