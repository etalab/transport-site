defmodule Transport.IRVE.ReportItem do
  @moduledoc """
  Struct representing one IRVE resource in the consolidation report. The `ReportItem`
  let the data consumer indicate whether a resource has been included or not, and if not,
  why, along with some useful stats.
  """
  @enforce_keys [:dataset_id, :resource_id, :resource_url, :estimated_pdc_count, :extension]
  defstruct [:dataset_id, :resource_id, :resource_url, :error, :estimated_pdc_count, :extension]
end
