defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias DB.{Dataset, Resource, Validation}
  alias TransportWeb.PaginationHelpers
  alias TransportWeb.Router.Helpers
  import Phoenix.Controller, only: [current_path: 1, current_url: 2]

  def render_sidebar_from_type(conn, dataset), do: render_panel_from_type(conn, dataset, "sidebar")

  def render_panel_from_type(conn, dataset, panel_type) do
    type =
      if Resource.is_transit_file?(dataset.type) do
        "public-transit"
      else
        dataset.type
      end

    render_existing(
      TransportWeb.DatasetView,
      "_#{panel_type}_#{type}.html",
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

  def region_link(conn, region) do
    region_id = Integer.to_string(region.id)

    case conn.params do
      %{"region" => ^region_id} ->
        ~E"<span class=\"activefilter\"><%= region.nom %> (<%= region.count %>)</span>"

      _ ->
        link(
          "#{region.nom} (#{region.count})",
          to: dataset_path(conn, :by_region, region.id)
        )
    end
  end

  def area_type_link(conn, zone_type) do
    msg =
      %{
        "urban_public_transport" => dgettext("page-shortlist", "Urban public transport"),
        "intercities_public_transport" => dgettext("page-shortlist", "Intercities public transport")
      }[zone_type]

    case conn.params do
      %{"filter" => ^zone_type} -> ~E"<span class=\"activefilter\"><%= msg %></span>"
      _ -> link(msg, to: dataset_path(conn, :index, filter: zone_type))
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
      "long-distance-coach" -> "/images/icons/bus.svg"
      "bike-sharing" -> "/images/icons/bicycle.svg"
      "carsharing-areas" -> "/images/icons/car.svg"
      "charging-stations" -> "/images/icons/charge-station.svg"
      "air-transport" -> "/images/icons/plane.svg"
      "road-network" -> "/images/icons/map.svg"
      _ -> nil
    end
  end

  def display_all_regions_links?(%{params: %{"region" => region}}) when not is_nil(region), do: true
  def display_all_regions_links?(_), do: false

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

  def is_transit_file?(%Dataset{type: type}), do: Resource.is_transit_file?(type)

  def licence(dataset) do
    Dataset.localise_licence(dataset)
  end

  def licence_url("fr-lo"), do: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf"
  def licence_url("odc-odbl"), do: "https://opendatacommons.org/licenses/odbl/1.0/"
  def licence_url(_), do: nil

  @spec localization(DB.Dataset.t()) :: binary | nil
  defp localization(%Dataset{aom: %{nom: nom}}), do: nom
  defp localization(%Dataset{region: %{nom: nom}}), do: nom
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
end
