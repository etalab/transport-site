defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  use PhoenixHtmlSanitizer, :strip_tags
  alias DB.{Dataset, Resource, Validation}
  alias TransportWeb.PaginationHelpers
  alias TransportWeb.Router.Helpers
  import Phoenix.Controller, only: [current_path: 1, current_url: 2]

  def render_sidebar_from_type(conn, dataset), do: render_panel_from_type(conn, dataset, "sidebar")

  def render_panel_from_type(conn, dataset, panel_type) do
    render_existing(
      TransportWeb.DatasetView,
      "_#{panel_type}_#{dataset.type}.html",
      dataset: dataset,
      conn: conn
    )
  end

  def format_date(nil), do: ""

  def format_date(date) do
    date
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.format!("{0D}/{0M}/{YYYY}")
  end

  def get_name(%{"organization" => organization}), do: organization["name"]
  def get_name(%{"owner" => owner}), do: owner["first_name"] <> " " <> owner["last_name"]

  def first_gtfs(dataset) do
    dataset
    |> Dataset.valid_gtfs()
    |> List.first()
  end

  def end_date(dataset) do
    dataset
    |> Dataset.valid_gtfs()
    |> Enum.max_by(
      fn
        %{metadata: nil} -> ""
        %{metadata: metadata} -> metadata["end_date"]
        _ -> ""
      end,
      fn -> nil end
    )
    |> case do
      nil -> ""
      resource -> resource.metadata["end_date"]
    end
  end

  def pagination_links(%{path_info: ["datasets", "region", region]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_region] |> add_order_by(conn.params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [region],
      kwargs
    )
  end

  def pagination_links(%{path_info: ["datasets", "aom", aom]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_aom] |> add_order_by(conn.params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [aom],
      kwargs
    )
  end

  def pagination_links(conn, paginator) do
    PaginationHelpers.pagination_links(conn, paginator)
  end

  def order_link(conn, order_by) do
    msg =
      %{
        "alpha" => dgettext("page-shortlist", "Alphabetical"),
        "most_recent" => dgettext("page-shortlist", "Most recent")
      }[order_by]

    case conn.assigns do
      %{order_by: ^order_by} -> ~E"<span class=\"activefilter\"><%= msg %></span>"
      _ -> link(msg, to: current_url(conn, Map.put(conn.params, "order_by", order_by)))
    end
  end

  def type_link(conn, %{type: type, msg: msg}) do
    case conn.params do
      %{"type" => ^type} -> ~E"<span class=\"activefilter\"><%= msg %></span>"
      _ -> link(msg, to: dataset_path(conn, :index, type: type))
    end
  end

  def icon_type_path(%{type: type}) do
    case type do
      "public-transit" -> "/images/icons/bus.svg"
      "bike-sharing" -> "/images/icons/bicycle.svg"
      "carsharing-areas" -> "/images/icons/car.svg"
      "charging-stations" -> "/images/icons/charge-station.svg"
      "air-transport" -> "/images/icons/plane.svg"
      "road-network" -> "/images/icons/map.svg"
      "addresses" -> "/images/icons/addresses.svg"
      _ -> nil
    end
  end

  def display_all_types_links?(%{params: %{"type" => type}}) when not is_nil(type), do: true
  def display_all_types_links?(_), do: false

  defp add_order_by(kwargs, %{"order_by" => order}), do: Keyword.put(kwargs, :order_by, order)
  defp add_order_by(kwargs, _), do: kwargs

  def summary_class(%{count_errors: 0}), do: "resource__summary--Success"
  def summary_class(%{severity: severity}), do: "resource__summary--#{severity}"

  def gtfs_resources(%{resources: resources}), do: Enum.filter(resources, &Resource.is_gtfs?/1)
  def gbfs_resources(%{resources: resources}), do: Enum.filter(resources, &Resource.is_gbfs?/1)
  def netex_resources(%{resources: resources}), do: Enum.filter(resources, &Resource.is_netex?/1)

  def other_resources(%{resources: resources}) do
    resources
    |> Stream.reject(&Resource.is_gtfs?/1)
    |> Stream.reject(&Resource.is_gbfs?/1)
    |> Stream.reject(&Resource.is_netex?/1)
    |> Enum.to_list()
  end

  def licence_url("fr-lo"), do: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf"
  def licence_url("odc-odbl"), do: "https://opendatacommons.org/licenses/odbl/1.0/"
  def licence_url(_), do: nil

  @spec localization(DB.Dataset.t()) :: binary | nil
  defp localization(%Dataset{aom: %{nom: nom}}), do: nom
  defp localization(%Dataset{region: %{nom: nom}}), do: nom

  defp localization(%Dataset{associated_territory_name: associated_territory_name}),
    do: associated_territory_name

  defp localization(_), do: nil

  @doc """
  long_title of the dataset, used in the dataset list and dataset detail as the 'main' title of the dataset
  """
  def long_title(%Dataset{} = dataset) do
    localization = localization(dataset)

    if localization do
      localization <> " - " <> Dataset.type_to_str(dataset.type)
    else
      Dataset.type_to_str(dataset.type)
    end
  end

  def description(%Dataset{} = dataset) do
    {:safe, sanitized_md} = sanitize(dataset.description)

    sanitized_md
    |> Earmark.as_html!()
    |> raw()
  end

  @doc """
  Builds a licence.
  ## Examples
      iex> %Dataset{licence: "fr-lo"}
      ...> |> Dataset.licence
      "Open Licence"
      iex> %Dataset{licence: "Libertarian"}
      ...> |> Dataset.licence
      "Not specified"
  """
  @spec licence(%Dataset{}) :: String.t()
  def licence(%Dataset{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("dataset", "fr-lo")
      "odc-odbl" -> dgettext("dataset", "odc-odbl")
      "other-open" -> dgettext("dataset", "other-open")
      _ -> dgettext("dataset", "notspecified")
    end
  end
end
