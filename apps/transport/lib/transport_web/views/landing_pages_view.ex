defmodule TransportWeb.LandingPagesView do
  use TransportWeb, :view

  def gbfs_abbreviation(text) do
    text |> abbreviation("GBFS", "Standard General Bikeshare Feed Specification")
  end

  def aoms_abbreviation(text) do
    aoms = dgettext("landing-vls", "Autorités Organisatrices de la Mobilité: Mobility Organizing Authorities")
    text |> abbreviation("AOMs", aoms)
  end

  defp abbreviation(text, abbreviation, explanation) do
    String.replace(text, abbreviation, "<abbr class=\"inline-help\" title=\"#{explanation}\">#{abbreviation}</abbr>")
  end

  def homepage_link(text) do
    String.replace(
      text,
      "transport.data.gouv.fr",
      "<a href=\"https://transport.data.gouv.fr\">transport.data.gouv.fr</a>"
    )
  end

  def format_integer(number) do
    Helpers.format_number(number)
  end
end
