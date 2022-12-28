defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias DB.{Dataset, Resource}
  alias Plug.Conn.Query
  alias TransportWeb.{MarkdownHandler, PaginationHelpers, ResourceView, Router.Helpers}
  import Phoenix.Controller, only: [current_path: 1, current_path: 2, current_url: 2]
  # NOTE: ~H is defined in LiveView, but can actually be used from anywhere.
  # ~H expects a variable named `assigns`, so wrapping the calls to `~H` inside
  # a helper function would be cleaner and more future-proof to avoid conflicts at some point.
  import Phoenix.Component, only: [sigil_H: 2]
  import DB.MultiValidation, only: [get_metadata_info: 2, get_metadata_info: 3, get_metadata_modes: 2]
  alias Shared.DateTimeDisplay
  alias Transport.Validators.GTFSTransport

  @gtfs_rt_validator_name Transport.Validators.GTFSRT.validator_name()

  @doc """
  Count the number of resources (official + community), excluding resources with a `documentation` type.
  """
  @spec count_resources(Dataset.t()) :: non_neg_integer
  def count_resources(dataset) do
    nb_resources = Enum.count(official_available_resources(dataset))
    nb_community_resources = Enum.count(community_resources(dataset))
    nb_resources + nb_community_resources - count_documentation_resources(dataset)
  end

  @spec count_documentation_resources(Dataset.t()) :: non_neg_integer
  def count_documentation_resources(dataset) do
    dataset |> official_available_resources() |> Stream.filter(&Resource.is_documentation?/1) |> Enum.count()
  end

  @spec count_discussions(any) :: [45, ...] | non_neg_integer
  @doc """
  Count the number of discussions if they are available
  """
  def count_discussions(nil), do: '-'
  def count_discussions(discussions), do: Enum.count(discussions)

  def end_date(dataset) do
    dataset.resources
    |> Enum.filter(&Resource.is_gtfs?/1)
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
    kwargs = [path: &Helpers.dataset_path/4, action: :by_region] |> add_query_params(conn.query_params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [region],
      kwargs
    )
  end

  def pagination_links(%{path_info: ["datasets", "aom", aom]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_aom] |> add_query_params(conn.query_params)

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

    assigns = Plug.Conn.assign(conn, :msg, msg).assigns()

    case assigns do
      %{order_by: ^order_by} -> ~H{<span class="activefilter"><%= @msg %></span>}
      _ -> link(msg, to: current_url(conn, Map.put(conn.query_params, "order_by", order_by)))
    end
  end

  def licence_link(%Plug.Conn{} = conn, %{licence: "all", count: count}) do
    assigns = Plug.Conn.assign(conn, :count, count).assigns()

    if Map.has_key?(conn.query_params, "licence") do
      link("#{dgettext("page-shortlist", "All (feminine)")} (#{count})",
        to: current_url(conn, Map.reject(conn.query_params, fn {k, _v} -> k == "licence" end))
      )
    else
      ~H{<span class="activefilter"><%= dgettext("page-shortlist", "All (feminine)") %> (<%= @count %>)</span>}
    end
  end

  def licence_link(%Plug.Conn{} = conn, %{licence: licence, count: count}) when licence not in ["fr-lo", "lov2"] do
    assigns = Plug.Conn.merge_assigns(conn, count: count, name: name = licence(%Dataset{licence: licence})).assigns()

    if Map.get(conn.query_params, "licence") == licence do
      ~H{<span class="activefilter"><%= @name %> (<%= @count %>)</span>}
    else
      link("#{name} (#{count})", to: current_url(conn, Map.put(conn.query_params, "licence", licence)))
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

    assigns = Plug.Conn.merge_assigns(conn, count: count, nom: nom).assigns()

    case current_path(conn, %{}) do
      ^url -> ~H{<span class="activefilter"><%= @nom %> (<%= @count %>)</span>}
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
    assigns = Plug.Conn.merge_assigns(conn, count: count, msg: msg).assigns()
    active_filter_text = ~H{<span class="activefilter"><%= @msg %> (<%= @count %>)</span>}

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

    assigns = Plug.Conn.merge_assigns(conn, count: count, msg: msg).assigns()

    case {only_rt, Map.get(conn.query_params, "filter")} do
      {false, "has_realtime"} -> link("#{msg} (#{count})", to: full_url)
      {true, nil} -> link("#{msg} (#{count})", to: full_url)
      _ -> ~H{<span class="activefilter"><%= @msg %> (<%= @count %>)</span>}
    end
  end

  def icon_type_path(%{type: type}) do
    # If you add an upcoming type be sure to add the black and the grey version.
    # The upcoming ("grey") version should be named `<filename>-grey.svg`
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
      "car-motorbike-sharing" => "car-motorbike-sharing.svg",
      "low-emission-zones" => "low-emission-zones.svg",
      "bike-parking" => "bike-parking.svg",
      "transport-traffic" => "transport-traffic.svg",
      # Not proper types, but modes/filters
      "real-time-public-transit" => "bus-stop.svg",
      "long-distance-coach" => "bus.svg",
      "train" => "train.svg",
      "boat" => "boat.svg"
    }

    if Map.has_key?(icons, type), do: "/images/icons/#{Map.get(icons, type)}"
  end

  def icon_type_path(type) when is_binary(type), do: icon_type_path(%{type: type})

  def upcoming_icon_type_path(type) when is_binary(type) do
    String.replace(icon_type_path(type), ".svg", "-grey.svg")
  end

  def display_all_types_links?(%{params: %{"type" => type}}) when not is_nil(type), do: true
  def display_all_types_links?(_), do: false

  defp add_query_params(kwargs, params) do
    kwargs |> Keyword.merge(for {key, value} <- params, do: {String.to_atom(key), value})
  end

  def gbfs_documentation_link(version) when is_binary(version) do
    "https://github.com/NABSA/gbfs/blob/v#{version}/gbfs.md"
  end

  def gbfs_feed_source_for_ttl(types) do
    feed_name = Transport.Shared.GBFSMetadata.feed_to_use_for_ttl(types)
    if feed_name, do: feed_name, else: "root"
  end

  # For GTFS resources
  def summary_class(%{count_errors: 0}), do: "resource__summary--Success"
  def summary_class(%{severity: severity}), do: "resource__summary--#{severity}"

  def summary_class(%DB.MultiValidation{result: %{"errors_count" => errors_count}})
      when is_integer(errors_count) and errors_count > 0 do
    "resource__summary--Error"
  end

  def summary_class(%DB.MultiValidation{result: %{"warnings_count" => warnings_count}})
      when is_integer(warnings_count) and warnings_count > 0 do
    "resource__summary--Warning"
  end

  def summary_class(%DB.MultiValidation{}), do: "resource__summary--Success"

  def warnings_count(%DB.MultiValidation{result: %{"warnings_count" => warnings_count}})
      when is_integer(warnings_count) and warnings_count >= 0,
      do: warnings_count

  def warnings_count(%DB.MultiValidation{validator: @gtfs_rt_validator_name}), do: 0
  def warnings_count(%DB.MultiValidation{}), do: nil

  def errors_count(%DB.MultiValidation{result: %{"errors_count" => errors_count}})
      when is_integer(errors_count) and errors_count >= 0,
      do: errors_count

  def availability_number_days, do: 30
  def max_nb_history_resources, do: 25

  def availability_ratio_class(ratio) when ratio >= 0 and ratio <= 100 do
    cond do
      ratio >= 99 -> "resource__summary--Success"
      ratio >= 95 -> "resource__summary--Warning"
      true -> "resource__summary--Error"
    end
  end

  def outdated_class(true = _is_outdated), do: "resource__summary--Error"
  def outdated_class(_), do: ""

  def valid_panel_class(%DB.Resource{is_available: false}, _), do: "invalid-resource-panel"

  def valid_panel_class(%DB.Resource{} = r, is_outdated) do
    if Resource.is_gtfs?(r) && is_outdated do
      "invalid-resource-panel"
    else
      ""
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

  def schemas_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Enum.filter(&Resource.has_schema?/1)
    |> Enum.sort_by(& &1.display_position)
  end

  def other_official_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Stream.reject(&Resource.is_gtfs?/1)
    |> Stream.reject(&Resource.is_netex?/1)
    |> Stream.reject(&Resource.is_real_time?/1)
    |> Stream.reject(&Resource.is_documentation?/1)
    |> Stream.reject(&Resource.has_schema?/1)
    |> Enum.to_list()
    |> Enum.sort_by(& &1.display_position)
  end

  def official_documentation_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Enum.filter(&Resource.is_documentation?/1)
  end

  def is_real_time_public_transit?(%Dataset{type: "public-transit"} = dataset) do
    not Enum.empty?(real_time_official_resources(dataset))
  end

  def is_real_time_public_transit?(%Dataset{}), do: false

  def community_resources(dataset), do: Dataset.community_resources(dataset)

  def licence_url(licence) when licence in ["fr-lo", "lov2"],
    do: "https://www.etalab.gouv.fr/licence-ouverte-open-licence/"

  def licence_url("odc-odbl"), do: "https://opendatacommons.org/licenses/odbl/1.0/"

  def licence_url("mobility-licence"),
    do: "https://wiki.lafabriquedesmobilites.fr/wiki/Licence_Mobilités"

  def licence_url(_), do: nil

  @spec description(Dataset.t() | Resource.t()) :: Phoenix.HTML.safe()
  def description(instance) do
    instance.description
    |> markdown_to_safe_html!()
  end

  def markdown_to_safe_html!(md), do: MarkdownHandler.markdown_to_safe_html!(md)

  @doc """
  Builds a licence.

  ## Examples

  iex> licence(%Dataset{licence: "fr-lo"})
  "Licence Ouverte — version 1.0"
  iex> licence(%Dataset{licence: "lov2"})
  "Licence Ouverte — version 2.0"
  iex> licence(%Dataset{licence: "Libertarian"})
  "Libertarian"
  """
  @spec licence(Dataset.t()) :: String.t()
  def licence(%Dataset{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("dataset", "fr-lo")
      "licence-ouverte" -> dgettext("dataset", "licence-ouverte")
      "odc-odbl" -> dgettext("dataset", "odc-odbl")
      "other-open" -> dgettext("dataset", "other-open")
      "lov2" -> dgettext("dataset", "lov2")
      "notspecified" -> dgettext("dataset", "notspecified")
      "mobility-licence" -> dgettext("dataset", "Mobility Licence")
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
    |> Enum.reject(fn r -> Resource.is_community_resource?(r) or Resource.is_documentation?(r) end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "bike-scooter-sharing", resources: resources}) do
    resources
    |> Enum.filter(fn r -> r.format == "gbfs" or String.ends_with?(r.url, "gbfs.json") end)
    |> Enum.reject(fn r ->
      String.contains?(r.url, "station_status") or String.contains?(r.url, "station_information") or
        Resource.is_community_resource?(r) or Resource.is_documentation?(r)
    end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "low-emission-zones", resources: resources}) do
    resources
    |> Enum.filter(fn r ->
      r.schema_name == "etalab/schema-zfe" or r.format == "geojson" or
        String.contains?(String.downcase(r.title), "geojson")
    end)
    # Display zones and not special roads
    |> Enum.reject(fn r ->
      String.contains?(r.url, "voie") or Resource.is_community_resource?(r) or Resource.is_documentation?(r)
    end)
    |> Enum.max_by(fn r -> r.last_update end, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{}), do: nil

  def resource_tooltip_content(%DB.Resource{is_available: false}),
    do: dgettext("dataset", "The resource is not available (maybe temporarily)")

  def resource_tooltip_content(%DB.Resource{}), do: nil

  def resource_span_class(%DB.Resource{is_available: false}), do: "span-unavailable"
  def resource_span_class(%DB.Resource{}), do: nil

  def resource_class(false = _is_available, _), do: "resource--unavailable"
  def resource_class(_, true = _is_outdated), do: "resource--outdated"
  def resource_class(_, false = _is_outdated), do: "resource--valid"
  def resource_class(_, _), do: ""

  def order_resources_by_validity(resources, %{validations: validations}) do
    Enum.sort_by(resources, &(validations |> Map.get(&1.id) |> hd() |> get_metadata_info("end_date")), &>=/2)
  end

  def order_resources_by_format(resources) do
    formats = resources |> Enum.map(& &1.format) |> MapSet.new()

    if MapSet.equal?(formats, MapSet.new(["GTFS", "NeTEx"])) do
      resources
    else
      resources |> Enum.sort_by(& &1.format, &>=/2)
    end
  end

  def documentation_url(%Resource{schema_name: schema_name, schema_version: schema_version}) do
    Transport.Shared.Schemas.documentation_url(schema_name, schema_version)
  end

  def schema_label(%{schema_name: schema_name, schema_version: schema_version}) when not is_nil(schema_version) do
    "#{schema_name} (#{schema_version})"
  end

  def schema_label(%{schema_name: schema_name}), do: schema_name

  def has_validity_period?(history_resources) when is_list(history_resources) do
    history_resources |> Enum.map(&has_validity_period?/1) |> Enum.any?()
  end

  def has_validity_period?(%DB.ResourceHistory{} = resource_history) do
    case validity_period(resource_history) do
      %{"start_date" => start_date, "end_date" => end_date} when not is_nil(start_date) and not is_nil(end_date) -> true
      _ -> false
    end
  end

  def validity_period(%DB.ResourceHistory{
        validations: [
          %{metadata: %DB.ResourceMetadata{metadata: %{"start_date" => start_date, "end_date" => end_date}}}
        ]
      }) do
    %{"start_date" => start_date, "end_date" => end_date}
  end

  def validity_period(_), do: %{}

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

  def publish_community_resource_url(%DB.Dataset{datagouv_id: datagouv_id}) do
    :transport
    |> Application.fetch_env!(:datagouvfr_site)
    |> Path.join("/admin/community-resource/new/?dataset_id=#{datagouv_id}")
  end

  def multi_validation_performed?(%DB.MultiValidation{result: %{"validation_performed" => false}}), do: false
  def multi_validation_performed?(%DB.MultiValidation{}), do: true
  def multi_validation_performed?(nil), do: false

  @doc """
  Determines if we should display "specific usage conditions" for a dataset.
  We displays it only for datasets under the ODbL license that are not OSM exports. We use the `openstreetmap` tag as a proxy of "this is an export from OSM".

  ## Examples

  iex> displays_odbl_specific_usage_conditions?(%Dataset{licence: "odc-odbl", tags: ["foo"]})
  true
  iex> displays_odbl_specific_usage_conditions?(%Dataset{licence: "odc-odbl", tags: ["foo", "openstreetmap"]})
  false
  """
  def displays_odbl_specific_usage_conditions?(%Dataset{licence: "odc-odbl", tags: tags}) do
    "openstreetmap" not in tags
  end

  def displays_odbl_specific_usage_conditions?(%Dataset{}), do: false
end
