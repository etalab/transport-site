defmodule Transport.IRVE.Static.Probes do
  @moduledoc """
  This module groups functions related to IRVE-specific CSV handling.
  """

  @doc """
  A quick way to grab the first line of a CSV (in order to analyze headers without going through a proper parser)
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
  Attempt to detect column separator on a v2+ file, by looking at what is around `id_pdc_itinerance`.

  Remove double-quotes, in case they are here.

  Works whether `id_pdc_itinerance` is the first column or not.

  ## Examples

  iex> Transport.IRVE.Static.Probes.hint_header_separator("nom_amenageur;id_pdc_itinerance;nom_station")
  ";"

  iex> Transport.IRVE.Static.Probes.hint_header_separator("id_pdc_itinerance,nom_station,adresse")
  ","

  """
  def hint_header_separator(body) do
    trimmed_first_line = body |> first_line() |> String.replace(~S("), "")
    case Regex.scan(~r/(.)id_pdc_itinerance|id_pdc_itinerance(.)/, trimmed_first_line) do
      # regular case where the separator is before the field name
      [[_, separator, ""]] -> separator  # separator before id_pdc_itinerance
      # rare edge case where `id_pdc_itinerance` is the first column of the file
      # separator is after `id_pdc_itinerance` in that case
      [[_, "", separator]] -> separator
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
