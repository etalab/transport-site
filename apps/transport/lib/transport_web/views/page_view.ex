defmodule TransportWeb.PageView do
  use TransportWeb, :view

  def current_tiles(tiles), do: Enum.filter(tiles, &(&1.count > 0))

  def upcoming_tiles(tiles) do
    Enum.filter(tiles, &(&1.count == 0 and is_binary(&1.type)))
  end

  def class("y"), do: "good"
  def class(_), do: "bad"

  def thumb("y"), do: "👍"
  def thumb(_), do: "👎"

  def make_link(""), do: "—"
  def make_link(o), do: link("Lien", to: o)

  @doc """
  iex> nb_downloads_for_humans(2_400_420, "fr")
  "2 M"
  iex> nb_downloads_for_humans(215_500, "fr")
  "216 k"
  iex> nb_downloads_for_humans(1_200, "fr")
  "1 k"
  iex> nb_downloads_for_humans(623, "fr")
  "623"
  """
  def nb_downloads_for_humans(value, locale) do
    Transport.Cldr.Number.to_string!(value, format: :short, locale: locale)
  end

  @doc """
  iex> types = TransportWeb.API.Schemas.AutocompleteItem.types()
  iex> Enum.each(types, fn type -> Map.fetch!(autocomplete_translations(), type) end)
  :ok
  """
  def autocomplete_translations do
    %{
      "region" => dgettext("autocomplete", "region"),
      "departement" => dgettext("autocomplete", "departement"),
      "epci" => dgettext("autocomplete", "epci"),
      "commune" => dgettext("autocomplete", "commune"),
      "feature" => dgettext("autocomplete", "feature"),
      "mode" => dgettext("autocomplete", "mode"),
      "offer" => dgettext("autocomplete", "offer"),
      "format" => dgettext("autocomplete", "format"),
      "dataset" => dgettext("autocomplete", "dataset"),
      "search-description" => dgettext("autocomplete", "search-description"),
      "results-description" => dgettext("autocomplete", "results-description")
    }
  end
end
