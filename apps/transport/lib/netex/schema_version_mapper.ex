defmodule Transport.NeTEx.SchemaVersionMapper do
  @moduledoc """
  Maps a publication date to the NeTEx XSD version to validate against.

  French Profile 2.5 (→ NeTEx 2.0) is expected Dec 2026 with a 6-month grace
  period until June 2027. Archives published during the grace period are
  validated against the old XSD to avoid penalizing producers who haven't
  upgraded yet.

  Returns `"v1.3.2"` for dates before June 2027, `"v2.0.0"` otherwise.
  """

  @spec xsd_version_for_date(Date.t()) :: binary()
  def xsd_version_for_date(%Date{year: year, month: month, day: day})
      when {year, month, day} < {2027, 6, 1},
      do: "v1.3.2"

  def xsd_version_for_date(_), do: "v2.0.0"
end
