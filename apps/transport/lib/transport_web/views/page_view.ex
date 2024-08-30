defmodule TransportWeb.PageView do
  use TransportWeb, :view
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]
  import TransportWeb.DatasetView, only: [upcoming_icon_type_path: 1]

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

  @spec show_proxy_stats_block?([DB.Dataset.t()]) :: boolean()
  def show_proxy_stats_block?(datasets) do
    datasets |> Enum.flat_map(& &1.resources) |> Enum.any?(&DB.Resource.served_by_proxy?/1)
  end

  @spec show_downloads_stats?(DB.Dataset.t()) :: boolean()
  def show_downloads_stats?(%DB.Dataset{resources: resources}) do
    Enum.any?(resources, &DB.Resource.hosted_on_datagouv?/1)
  end

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

  def dataset_creation,
  do:
    :transport
    |> Application.fetch_env!(:datagouvfr_site)
    |> Path.join("/fr/admin/dataset/new/")
end
