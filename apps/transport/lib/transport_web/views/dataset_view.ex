defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias DB.{Dataset, Resource, Validation}
  alias Plug.Conn.Query
  alias TransportWeb.MarkdownHandler
  alias TransportWeb.PaginationHelpers
  alias TransportWeb.Router.Helpers
  import Phoenix.Controller, only: [current_path: 1, current_path: 2, current_url: 2]
  # NOTE: ~H is defined in LiveView, but can actually be used from anywhere.
  # ~H expects a variable named `assigns`, so wrapping the calls to `~H` inside
  # a helper function would be cleaner and more future-proof to avoid conflicts at some point.
  import Phoenix.LiveView.Helpers, only: [sigil_H: 2]
  import Transport.GbfsUtils, only: [gbfs_validation_link: 1]
  alias Shared.DateTimeDisplay
  alias TransportWeb.ResourceView

  @doc """
  Count the number of resources (official + community)
  """
  def count_resources(dataset) do
    Enum.count(official_available_resources(dataset)) + Enum.count(community_resources(dataset))
  end

  @spec count_discussions(any) :: [45, ...] | non_neg_integer
  @doc """
  Count the number of discussions if they are available
  """
  def count_discussions(nil), do: '-'
  def count_discussions(discussions), do: Enum.count(discussions)

  def render_sidebar_from_type(conn, dataset),
    do: render_panel_from_type(conn, dataset, "sidebar")

  def render_panel_from_type(conn, dataset, panel_type) do
    render_existing(
      TransportWeb.DatasetView,
      "_#{panel_type}_#{dataset.type}.html",
      dataset: dataset,
      conn: conn
    )
  end

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
        "most_recent" => dgettext("page-shortlist", "Most recently added")
      }[order_by]

    case assigns = conn.assigns do
      %{order_by: ^order_by} -> ~H"<span class=\"activefilter\"><%= msg %></span>
"
      _ -> link(msg, to: "#{current_url(conn, Map.put(conn.query_params, "order_by", order_by))}")
    end
  end

  def region_link(conn, %{nom: nom, count: count, id: id}) do
    url =
      case id do
        nil -> dataset_path(conn, :index)
        _ -> dataset_path(conn, :by_region, id)
      end

    params = conn.query_params
    full_url = "#{url}?#{Query.encode(params)}"

    assigns = conn.assigns

    case current_path(conn, %{}) do
      ^url -> ~H"<span class=\"activefilter\"><%= nom %> (<%= count %>)</span>
"
      _ -> link("#{nom} (#{count})", to: full_url)
    end
  end

  def type_link(conn, %{type: type, msg: msg, count: count}) do
    params =
      case type do
        nil -> conn.query_params |> Map.delete("type")
        type -> conn.query_params |> Map.put("type", type)
      end

    full_url =
      conn.request_path
      |> URI.parse()
      |> Map.put(:query, Query.encode(params))
      |> URI.to_string()

    link_text = "#{msg} (#{count})"
    assigns = conn.assigns
    active_filter_text = ~H"<span class=\"activefilter\"><%= msg %> (<%= count %>)</span>
"

    case conn.params do
      %{"type" => ^type} ->
        active_filter_text

      %{"type" => _} ->
        link(link_text, to: full_url)

      _ ->
        case type do
          nil -> active_filter_text
          _ -> link(link_text, to: full_url)
        end
    end
  end

  def real_time_link(conn, %{only_realtime: only_rt, msg: msg, count: count}) do
    params =
      case only_rt do
        false -> conn.query_params |> Map.delete("filter")
        true -> conn.query_params |> Map.put(:filter, "has_realtime")
      end

    full_url =
      conn.request_path
      |> URI.parse()
      |> Map.put(:query, Query.encode(params))
      |> URI.to_string()
      |> Kernel.<>("#datasets-results")

    assigns = conn.assigns

    case {only_rt, Map.get(conn.query_params, "filter")} do
      {false, "has_realtime"} -> link("#{msg} (#{count})", to: full_url)
      {true, nil} -> link("#{msg} (#{count})", to: full_url)
      _ -> ~H"<span class=\"activefilter\"><%= msg %> (<%= count %>)</span>
"
    end
  end

  def icon_type_path(%{type: type}) do
    icons = %{
      "public-transit" => "bus.svg",
      "bike-scooter-sharing" => "bicycle-scooter.svg",
      "bike-way" => "bike-way.svg",
      "carpooling-areas" => "car.svg",
      "charging-stations" => "charge-station.svg",
      "air-transport" => "plane.svg",
      "road-data" => "roads.svg",
      "locations" => "locations.svg",
      "private-parking" => "parking.svg",
      "informations" => "infos.svg",
      "car-motorbike-sharing" => "car-motorbike-grey.svg",
      "low-emission-zones" => "low-emission-zones.svg",
      "bike-parking" => "bike-parking.svg",
      "mobility-counting" => "mobility-counting-grey.svg",
      # Not proper types, but modes/filters
      "real-time-public-transit" => "bus-stop.svg",
      "long-distance-coach" => "bus.svg",
      "train" => "train.svg",
      "boat" => "boat.svg"
    }

    if Map.has_key?(icons, type), do: "/images/icons/#{Map.get(icons, type)}"
  end

  def icon_type_path(type) when is_binary(type) do
    icon_type_path(%{type: type})
  end

  def display_all_types_links?(%{params: %{"type" => type}}) when not is_nil(type), do: true
  def display_all_types_links?(_), do: false

  defp add_order_by(kwargs, %{"order_by" => order}), do: Keyword.put(kwargs, :order_by, order)
  defp add_order_by(kwargs, _), do: kwargs

  def gbfs_documentation_link(version) when is_binary(version) do
    "https://github.com/NABSA/gbfs/blob/v#{version}/gbfs.md"
  end

  def gbfs_feed_source_for_ttl(%Resource{format: "gbfs", metadata: %{"types" => types}}) do
    feed_name = Transport.Shared.GBFSMetadata.feed_to_use_for_ttl(types)
    if feed_name, do: feed_name, else: "root"
  end

  # For GTFS resources
  def summary_class(%{count_errors: 0}), do: "resource__summary--Success"
  def summary_class(%{severity: severity}), do: "resource__summary--#{severity}"

  # For other resources
  def summary_class(%{metadata: %{"validation" => %{"has_errors" => false}}}),
    do: "resource__summary--Success"

  def summary_class(%{metadata: %{"validation" => %{"errors_count" => 0, "warnings_count" => warnings_count}}})
      when warnings_count > 0,
      do: "resource__summary--Warning"

  def summary_class(%{metadata: %{"validation" => _}}), do: "resource__summary--Error"

  def warnings_count(%Resource{metadata: %{"validation" => %{"warnings_count" => warnings_count}}})
      when is_integer(warnings_count) and warnings_count >= 0,
      do: warnings_count

  def warnings_count(%Resource{format: "gtfs-rt"}), do: 0
  def warnings_count(%Resource{}), do: nil

  def errors_count(%Resource{metadata: %{"validation" => %{"errors_count" => errors_count}}})
      when is_integer(errors_count) and errors_count >= 0,
      do: errors_count

  def errors_count(%Resource{}), do: nil

  def availability_number_days, do: 30

  def availability_ratio_class(ratio) when ratio >= 0 and ratio <= 100 do
    cond do
      ratio >= 99 -> "resource__summary--Success"
      ratio >= 95 -> "resource__summary--Warning"
      true -> "resource__summary--Error"
    end
  end

  def outdated_class(resource) do
    case Resource.is_outdated?(resource) do
      true -> "resource__summary--Error"
      false -> ""
    end
  end

  def valid_panel_class(%Resource{} = r) do
    case {Resource.is_gtfs?(r), Resource.valid_and_available?(r), Resource.is_outdated?(r)} do
      {true, false, _} -> "invalid-resource-panel"
      {true, _, true} -> "invalid-resource-panel"
      _ -> ""
    end
  end

  def official_available_resources(dataset),
    do:
      dataset
      |> Dataset.official_resources()
      |> Enum.filter(fn r -> r.is_available end)

  def gtfs_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.is_gtfs?/1)

  def unavailable_resources(dataset),
    do:
      dataset
      |> Dataset.official_resources()
      |> Enum.reject(fn r -> r.is_available end)

  def real_time_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.is_real_time?/1)

  def netex_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.is_netex?/1)

  def other_official_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Stream.reject(&Resource.is_gtfs?/1)
    |> Stream.reject(&Resource.is_netex?/1)
    |> Stream.reject(&Resource.is_real_time?/1)
    |> Enum.to_list()
    |> Enum.sort(fn r1, r2 ->
      nd1 = NaiveDateTime.from_iso8601(Map.get(r1, :last_update, ""))
      nd2 = NaiveDateTime.from_iso8601(Map.get(r2, :last_update, ""))

      case {nd1, nd2} do
        {{:ok, nd1}, {:ok, nd2}} -> NaiveDateTime.compare(nd1, nd2) == :gt
        _ -> true
      end
    end)
  end

  def community_resources(dataset), do: Dataset.community_resources(dataset)

  def licence_url("fr-lo"),
    do: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf"

  def licence_url("lov2"), do: "https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf"

  def licence_url("odc-odbl"), do: "https://opendatacommons.org/licenses/odbl/1.0/"

  def licence_url("mobility-license"),
    do: "https://download.data.grandlyon.com/licences/Licence_mobilit%C3%A9s_V_02_2021.pdf"

  def licence_url(_), do: nil

  @spec description(Dataset.t() | Resource.t()) :: Phoenix.HTML.safe()
  def description(instance) do
    instance.description
    |> markdown_to_safe_html!()
  end

  def markdown_to_safe_html!(md), do: MarkdownHandler.markdown_to_safe_html!(md)

  @doc """
  Builds a licence.
  It looks like fr-lo has been deprecrated by data.gouv and replaced by "lov2"
  If it is confirmed, we can remove it in the future.
  ## Examples
      iex> %Dataset{licence: "fr-lo"}
      ...> |> TransportWeb.DatasetView.licence
      "fr-lo"
      iex> %Dataset{licence: "Libertarian"}
      ...> |> TransportWeb.DatasetView.licence
      "Libertarian"
  """
  @spec licence(Dataset.t()) :: String.t()
  def licence(%Dataset{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("dataset", "fr-lo")
      "odc-odbl" -> dgettext("dataset", "odc-odbl")
      "other-open" -> dgettext("dataset", "other-open")
      "lov2" -> dgettext("dataset", "lov2")
      "notspecified" -> dgettext("dataset", "notspecified")
      "mobility-license" -> dgettext("dataset", "Mobility license")
      other -> other
    end
  end

  @doc """
  Returns the resources that need to be displayed on a map
  """
  @spec get_resource_to_display(Dataset.t()) :: Resource.t() | nil
  def get_resource_to_display(%Dataset{type: type, resources: resources})
      when type == "carpooling-areas" or type == "private-parking" or type == "charging-stations" do
    resources
    |> Enum.filter(fn r -> r.format == "csv" end)
    |> Enum.reject(fn r -> r.is_community_resource end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "bike-scooter-sharing", resources: resources}) do
    resources
    |> Enum.filter(fn r -> r.format == "gbfs" or String.ends_with?(r.url, "gbfs.json") end)
    |> Enum.reject(fn r -> String.contains?(r.url, "station_status") end)
    # credo:disable-for-next-line
    |> Enum.reject(fn r -> String.contains?(r.url, "station_information") end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "low-emission-zones", resources: resources}) do
    resources
    |> Enum.filter(fn r ->
      r.schema_name == "etalab/schema-zfe" or r.format == "geojson" or
        String.contains?(String.downcase(r.title), "geojson")
    end)
    # Display zones and not special roads
    |> Enum.reject(fn r -> String.contains?(r.url, "voie") end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{}), do: nil

  def resource_tooltip_content(%DB.Resource{is_available: false}),
    do: dgettext("dataset", "The resource is not available (maybe temporarily)")

  def resource_tooltip_content(%DB.Resource{}), do: nil

  def resource_span_class(%DB.Resource{is_available: false}), do: "span-unavailable"
  def resource_span_class(%DB.Resource{}), do: nil

  def resource_class(%DB.Resource{is_available: false}), do: "resource--unavailable"

  def resource_class(%DB.Resource{} = r) do
    case DB.Resource.valid_and_available?(r) do
      false ->
        "resource--notvalid"

      _ ->
        case DB.Resource.is_outdated?(r) do
          true -> "resource--outdated"
          false -> "resource--valid"
        end
    end
  end

  def order_resources_by_validity(resources) do
    resources
    |> Enum.sort_by(& &1.metadata["end_date"], &>=/2)
    |> Enum.sort_by(&Resource.valid_and_available?(&1), &>=/2)
  end

  def order_resources_by_format(resources), do: resources |> Enum.sort_by(& &1.format, &>=/2)

  def schema_url(%{schema_name: schema_name, schema_version: schema_version}) when not is_nil(schema_version) do
    "https://schema.data.gouv.fr/#{schema_name}/#{schema_version}/"
  end

  def schema_url(%{schema_name: schema_name}) do
    "https://schema.data.gouv.fr/#{schema_name}/latest.html"
  end

  def schema_label(%{schema_name: schema_name, schema_version: schema_version}) when not is_nil(schema_version) do
    "#{schema_name} (#{schema_version})"
  end

  def schema_label(%{schema_name: schema_name}), do: schema_name

  def download_url(%Plug.Conn{} = conn, %DB.Resource{} = resource) do
    cond do
      needs_stable_url?(resource) -> resource.latest_url
      Resource.can_direct_download?(resource) -> resource.url
      true -> resource_path(conn, :download, resource.id)
    end
  end

  defp needs_stable_url?(%DB.Resource{latest_url: nil}), do: false

  defp needs_stable_url?(%DB.Resource{url: url, filetype: "file"}) do
    Enum.member?(["static.data.gouv.fr", "demo-static.data.gouv.fr"], URI.parse(url).host)
  end

  defp needs_stable_url?(%DB.Resource{}), do: false

  def has_validity_period?(history_resources) when is_list(history_resources) do
    history_resources |> Enum.map(&has_validity_period?/1) |> Enum.any?()
  end

  def has_validity_period?(%DB.ResourceHistory{payload: %{"resource_metadata" => metadata}}) when is_map(metadata) do
    not is_nil(Map.get(metadata, "start_date"))
  end

  def has_validity_period?(%DB.ResourceHistory{}), do: false

  def show_resource_last_update(resources_updated_at, %DB.Resource{id: id} = resource, locale) do
    if Resource.is_real_time?(resource) do
      dgettext("page-dataset-details", "real-time")
    else
      resources_updated_at
      |> Map.get(id)
      |> case do
        nil -> dgettext("page-dataset-details", "unknown")
        dt -> dt |> DateTimeDisplay.format_datetime_to_date(locale)
      end
    end
  end
end
