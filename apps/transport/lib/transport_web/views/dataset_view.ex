defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias DB.{Dataset, Resource, Validation}
  alias Plug.Conn.Query
  alias TransportWeb.MarkdownHandler
  alias TransportWeb.PaginationHelpers
  alias TransportWeb.Router.Helpers
  import Phoenix.Controller, only: [current_path: 1, current_path: 2, current_url: 2]
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

  def format_datetime_to_date(nil), do: ""

  def format_datetime_to_date(datetime) do
    datetime
    |> Timex.parse!("{ISO:Extended}")
    |> Timex.format!("{0D}-{0M}-{YYYY}")
  end

  def format_date(nil), do: ""

  def format_date(date) do
    date
    |> Timex.parse!("{YYYY}-{0M}-{0D}")
    |> Timex.format!("{0D}-{0M}-{YYYY}")
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

    case conn.assigns do
      %{order_by: ^order_by} -> ~E"<span class=\"activefilter\"><%= msg %></span>"
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

    case current_path(conn, %{}) do
      ^url -> ~E"<span class=\"activefilter\"><%= nom %> (<%= count %>)</span>"
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
    active_filter_text = ~E"<span class=\"activefilter\"><%= msg %> (<%= count %>)</span>"

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

    case {only_rt, Map.get(conn.query_params, "filter")} do
      {false, "has_realtime"} -> link("#{msg} (#{count})", to: full_url)
      {true, nil} -> link("#{msg} (#{count})", to: full_url)
      _ -> ~E"<span class=\"activefilter\"><%= msg %> (<%= count %>)</span>"
    end
  end

  def icon_type_path(%{type: type}) do
    icons = %{
      "public-transit" => "/images/icons/bus.svg",
      "bike-sharing" => "/images/icons/bicycle.svg",
      "bike-path" => "/images/icons/bike-path.svg",
      "carpooling-areas" => "/images/icons/car.svg",
      "charging-stations" => "/images/icons/charge-station.svg",
      "air-transport" => "/images/icons/plane.svg",
      "road-network" => "/images/icons/map.svg",
      "addresses" => "/images/icons/addresses.svg",
      "private-parking" => "/images/icons/parking.svg",
      "stops-ref" => "/images/icons/addresses.svg",
      "informations" => "/images/icons/infos.svg"
    }

    Map.get(icons, type)
  end

  def display_all_types_links?(%{params: %{"type" => type}}) when not is_nil(type), do: true
  def display_all_types_links?(_), do: false

  defp add_order_by(kwargs, %{"order_by" => order}), do: Keyword.put(kwargs, :order_by, order)
  defp add_order_by(kwargs, _), do: kwargs

  def summary_class(%{count_errors: 0}), do: "resource__summary--Success"
  def summary_class(%{severity: severity}), do: "resource__summary--#{severity}"

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

  def gtfs_rt_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.is_gtfs_rt?/1)

  def gbfs_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.is_gbfs?/1)

  def netex_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.is_netex?/1)

  def other_official_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Stream.reject(&Resource.is_gtfs?/1)
    |> Stream.reject(&Resource.is_gtfs_rt?/1)
    |> Stream.reject(&Resource.is_gbfs?/1)
    |> Stream.reject(&Resource.is_netex?/1)
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
  def licence_url(_), do: nil

  @spec description(%Dataset{} | %Resource{}) :: Phoenix.HTML.safe()
  def description(instance) do
    instance.description
    |> MarkdownHandler.markdown_to_safe_html!()
  end

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
  @spec licence(%Dataset{}) :: String.t()
  def licence(%Dataset{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("dataset", "fr-lo")
      "odc-odbl" -> dgettext("dataset", "odc-odbl")
      "other-open" -> dgettext("dataset", "other-open")
      "lov2" -> dgettext("dataset", "lov2")
      "notspecified" -> dgettext("dataset", "notspecified")
      other -> other
    end
  end

  @doc """
  Returns the resources that need to be displayed on a map
  """
  @spec get_resource_to_display(%Dataset{}) :: Resource.t() | nil
  def get_resource_to_display(%Dataset{type: type, resources: resources})
      when type == "carpooling-areas" or type == "private-parking" or type == "charging-stations" do
    resources
    |> Enum.filter(fn r -> r.format == "csv" end)
    |> Enum.reject(fn r -> r.is_community_resource end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "bike-sharing", resources: resources}) do
    resources
    |> Enum.filter(fn r -> r.format == "gbfs" or String.ends_with?(r.url, "gbfs.json") end)
    |> Enum.reject(fn r -> r.is_community_resource end)
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

  def schema_url(%{schema_name: schema_name, schema_version: schema_version}) when not is_nil(schema_version) do
    "https://schema.data.gouv.fr/#{schema_name}/#{schema_version}.html"
  end

  def schema_url(%{schema_name: schema_name}) do
    "https://schema.data.gouv.fr/#{schema_name}/latest.html"
  end

  def schema_label(%{schema_name: schema_name, schema_version: schema_version}) when not is_nil(schema_version) do
    "#{schema_name} (#{schema_version})"
  end

  def schema_label(%{schema_name: schema_name}), do: schema_name
end
