defmodule Transport.IRVE.Static.Probes do
  @moduledoc """
  This module groups functions related to IRVE-specific CSV handling.
  """

  @doc """
  A quick way to grab the first line of a CSV (in order to analyze headers without going through a proper parser)

  iex> first_line("first,line\\nsome,data")
  "first,line"
  """
  def first_line(body) do
    body
    |> String.split("\n", parts: 2)
    |> hd()
  end

  @doc """
  A quick probe to evaluate if a content is likely to be v2+ schema-irve-statique data.

  Ref:
  - https://github.com/etalab/schema-irve/blob/v2.0.0/schema.json (which includes `id_pdc_itinerance`)
  - https://github.com/etalab/schema-irve/blob/v1.0.3/schema.json (which does not - instead we had `id_pdc`)
  """
  def has_id_pdc_itinerance(body) do
    body
    |> first_line()
    |> String.contains?("id_pdc_itinerance")
  end

  @doc """
  Attempt to detect column separator on a v2+ file, by looking at what is in front of `id_pdc_itinerance`.

  This is a early-stage version, which will be ultimately replaced by the approach taken in
  `Transport.IRVE.DataFrame.separators_frequencies`, but I don't want to do it right now since I
  want to ensure the whole data processing does not regress in the process.

  ### Examples

  Remove double-quotes, in case they are here.

  iex> hint_header_separator("nom_amenageur,id_pdc_itinerance,id_pdc_local")
  ","

  Must also work as the very first column (edge case seen on one file):

  iex> hint_header_separator("id_pdc_itinerance,id_pdc_local")
  ","

  If nothing works, should raise:

  iex> hint_header_separator("foobar")
  ** (RuntimeError) could not hint header separator from line (foobar)
  """
  def hint_header_separator(body) do
    trimmed_first_line = body |> first_line() |> String.replace(~S("), "")

    # usual case, then bogus case for 623ca46c13130c3228abd018, then error
    maybe_find_header_separator(~r/(.)id_pdc_itinerance/, trimmed_first_line) ||
      maybe_find_header_separator(~r/\Aid_pdc_itinerance(.)/, trimmed_first_line) ||
      raise "could not hint header separator from line (#{trimmed_first_line})"
  end

  def maybe_find_header_separator(regex, first_line) do
    case Regex.scan(regex, first_line) do
      [[_, sep]] -> sep
      [] -> nil
    end
  end

  @doc """
  Looking at the first line of the content, try to detect if we have a v1 file (which we do not support).

  This is done by detecting the presence of a v1-only field.

  See https://github.com/etalab/schema-irve/compare/v1.0.3...v2.0.0#diff-9fcde326d127f74194f70e563bdf2c118c51b719c308f015b8eb0204a9a552fbL72
  """
  def probably_v1_schema(body) do
    data = body |> first_line()

    # NOTE: do not use `n_amenageur`, because it will match in both v1 and v2 due to `siren_amenageur`
    !String.contains?(data, "nom_operateur") && String.contains?(data, "n_operateur")
  end
end
