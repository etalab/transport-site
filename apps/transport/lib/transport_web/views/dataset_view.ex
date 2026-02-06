defmodule TransportWeb.DatasetView do
  use TransportWeb, :view
  alias DB.{Dataset, Resource}
  alias Plug.Conn.Query
  alias TransportWeb.{MarkdownHandler, PaginationHelpers, ResourceView, Router.Helpers}
  import Ecto.Query
  import Phoenix.Controller, only: [current_path: 1, current_path: 2, current_url: 2]
  # NOTE: ~H is defined in LiveView, but can actually be used from anywhere.
  # ~H expects a variable named `assigns`, so wrapping the calls to `~H` inside
  # a helper function would be cleaner and more future-proof to avoid conflicts at some point.
  import Phoenix.Component, only: [sigil_H: 2, live_render: 3, assign: 3]
  import DB.Dataset, only: [experimental?: 1]
  import DB.MultiValidation, only: [get_metadata_info: 2, get_metadata_info: 3]
  alias Shared.DateTimeDisplay
  alias Transport.Validators.GTFSTransport
  alias Transport.Validators.MobilityDataGTFSValidator

  @gtfs_rt_validator_name Transport.Validators.GTFSRT.validator_name()

  @doc """
  Count the number of resources, excluding:
  - community resources
  - resources with a `documentation` type.
  """
  @spec count_resources(Dataset.t()) :: non_neg_integer
  def count_resources(dataset) do
    nb_official_resources = dataset |> official_available_resources() |> Enum.count()
    nb_official_resources - count_documentation_resources(dataset)
  end

  @spec count_documentation_resources(Dataset.t()) :: non_neg_integer
  def count_documentation_resources(dataset) do
    dataset |> official_available_resources() |> Stream.filter(&Resource.documentation?/1) |> Enum.count()
  end

  @spec count_discussions(any) :: [45, ...] | non_neg_integer
  @doc """
  Count the number of discussions if they are available
  """
  def count_discussions(nil), do: ~c"-"
  def count_discussions(discussions), do: Enum.count(discussions)

  def pagination_links(%{path_info: ["datasets", "region", region]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_region] |> add_query_params(conn.query_params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [region],
      kwargs
    )
  end

  def pagination_links(%{path_info: ["datasets", "epci", epci]} = conn, datasets) do
    kwargs = [path: &Helpers.dataset_path/4, action: :by_epci] |> add_query_params(conn.query_params)

    PaginationHelpers.pagination_links(
      conn,
      datasets,
      [epci],
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

    assigns = Plug.Conn.assign(conn, :msg, msg).assigns

    case assigns do
      %{order_by: ^order_by} -> ~H|<span class="activefilter">{@msg}</span>|
      _ -> link(msg, to: current_url(conn, Map.put(conn.query_params, "order_by", order_by)))
    end
  end

  def licence_link(%Plug.Conn{} = conn, %{licence: "all", count: count}) do
    assigns = Plug.Conn.assign(conn, :count, count).assigns

    if Map.has_key?(conn.query_params, "licence") do
      link("#{dgettext("page-shortlist", "All (feminine)")} (#{count})",
        to: current_url(conn, Map.reject(conn.query_params, fn {k, _v} -> k == "licence" end))
      )
    else
      ~H|<span class="activefilter">{dgettext("page-shortlist", "All (feminine)")} ({@count})</span>|
    end
  end

  def licence_link(%Plug.Conn{} = conn, %{licence: licence, count: count}) when licence not in ["fr-lo", "lov2"] do
    assigns = Plug.Conn.merge_assigns(conn, count: count, name: name = licence(%Dataset{licence: licence})).assigns

    if Map.get(conn.query_params, "licence") == licence do
      ~H|<span class="activefilter">{@name} ({@count})</span>|
    else
      link("#{name} (#{count})", to: current_url(conn, Map.put(conn.query_params, "licence", licence)))
    end
  end

  def region_link(conn, %{nom: nom, count: count, insee: insee}) do
    url =
      case insee do
        # This is for the "All" region
        nil -> dataset_path(conn, :index)
        _ -> dataset_path(conn, :by_region, insee)
      end

    params = conn.query_params
    full_url = "#{url}?#{Query.encode(params)}"

    assigns = Plug.Conn.merge_assigns(conn, count: count, nom: nom).assigns

    case current_path(conn, %{}) do
      ^url -> ~H|<span class="activefilter">{@nom} ({@count})</span>|
      _ -> link("#{nom} (#{count})", to: full_url)
    end
  end

  def legal_owners_links(conn, %DB.Dataset{legal_owners_aom: legal_owners_aom, legal_owners_region: legal_owners_region}) do
    legal_owners_region
    |> Enum.sort_by(& &1.nom)
    |> Enum.concat(legal_owners_aom |> Enum.sort_by(& &1.nom))
    |> Enum.map_join(", ", fn owner ->
      conn |> legal_owner_link(owner) |> safe_to_string()
    end)
    |> raw()
  end

  def legal_owner_link(conn, %DB.Region{nom: nom, insee: insee}) do
    link(nom, to: dataset_path(conn, :by_region, insee))
  end

  def legal_owner_link(conn, %DB.AOM{nom: nom, siren: siren}) do
    link(nom, to: dataset_path(conn, :by_epci, siren))
  end

  def type_link(conn, %{type: type, msg: msg, count: count}) do
    link_by_key(conn, "type", %{key: type, msg: msg, count: count})
  end

  def format_link(conn, %{format: format, msg: msg, count: count}) do
    link_by_key(conn, "format", %{key: format, msg: msg, count: count})
  end

  def subtype_link(conn, %{subtype: subtype, msg: msg, count: count}) do
    link_by_key(conn, "subtype", %{key: subtype, msg: msg, count: count})
  end

  defp link_by_key(conn, key_name, %{key: key, msg: msg, count: count}) do
    full_url =
      case key do
        nil -> current_url(conn, Map.delete(conn.query_params, key_name))
        key -> current_url(conn, Map.put(conn.query_params, key_name, key))
      end

    link_text = "#{msg} (#{count})"
    assigns = Plug.Conn.merge_assigns(conn, count: count, msg: msg).assigns
    active_filter_text = ~H|<span class="activefilter">{@msg} ({@count})</span>|

    case conn.params do
      %{^key_name => ^key} ->
        active_filter_text

      %{^key_name => _} ->
        link(link_text, to: full_url)

      _ ->
        if is_nil(key) do
          active_filter_text
        else
          link(link_text, to: full_url)
        end
    end
  end

  def real_time_link(conn, %{only_realtime: only_rt, msg: msg, count: count}) do
    full_url =
      case only_rt do
        false -> current_url(conn, Map.delete(conn.query_params, "filter"))
        true -> current_url(conn, Map.put(conn.query_params, "filter", "has_realtime"))
      end

    assigns = Plug.Conn.merge_assigns(conn, count: count, msg: msg).assigns

    case {only_rt, Map.get(conn.query_params, "filter")} do
      {false, "has_realtime"} -> link("#{msg} (#{count})", to: full_url)
      {true, nil} -> link("#{msg} (#{count})", to: full_url)
      _ -> ~H|<span class="activefilter">{@msg} ({@count})</span>|
    end
  end

  @doc """
  iex> DB.Dataset.types() |> Enum.map(&icon_type_path/1) |> Enum.filter(&is_nil/1)
  []
  """
  def icon_type_path(%{type: type}) do
    # If you add an upcoming type be sure to add the black and the grey version.
    # The upcoming ("grey") version should be named `<filename>-grey.svg`
    icons = %{
      "public-transit" => "bus.svg",
      "vehicles-sharing" => "vehicles-sharing.svg",
      "bike-data" => "bike-data.svg",
      "carpooling-areas" => "carpooling-areas.svg",
      "carpooling-lines" => "carpooling-lines.svg",
      "carpooling-offers" => "carpooling-offers.svg",
      "charging-stations" => "charge-station.svg",
      "road-data" => "roads.svg",
      "informations" => "infos.svg",
      "pedestrian-path" => "walk.svg"
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
    "https://github.com/MobilityData/gbfs/blob/v#{version}/gbfs.md"
  end

  def gbfs_feed_source_for_ttl(types) do
    feed_name = Transport.GBFSMetadata.feed_to_use_for_ttl(types)
    if feed_name, do: feed_name, else: "root"
  end

  # For GTFS resources
  @doc """
  iex> summary_class(%{severity: "Error"})
  "resource__summary--Error"
  iex> summary_class(%{severity: "ERROR"})
  "resource__summary--Error"
  """
  def summary_class(%{digest: %{"max_severity" => %{"max_level" => severity, "worst_occurrences" => count_errors}}}) do
    summary_class(%{count_errors: count_errors, severity: severity})
  end

  def summary_class(%{count_errors: 0}), do: "resource__summary--Success"
  def summary_class(%{severity: severity}), do: "resource__summary--#{String.capitalize(severity)}"

  def summary_class(%DB.MultiValidation{digest: %{"errors_count" => errors_count}})
      when is_integer(errors_count) and errors_count > 0 do
    "resource__summary--Error"
  end

  def summary_class(%DB.MultiValidation{digest: %{"warnings_count" => warnings_count}})
      when is_integer(warnings_count) and warnings_count > 0 do
    "resource__summary--Warning"
  end

  def summary_class(%DB.MultiValidation{result: %{"errors_count" => errors_count}})
      when is_integer(errors_count) and errors_count > 0 do
    "resource__summary--Error"
  end

  def summary_class(%DB.MultiValidation{result: %{"warnings_count" => warnings_count}})
      when is_integer(warnings_count) and warnings_count > 0 do
    "resource__summary--Warning"
  end

  def summary_class(%DB.MultiValidation{}), do: "resource__summary--Success"

  def warnings_count(%DB.MultiValidation{digest: %{"warnings_count" => warnings_count}})
      when is_integer(warnings_count) and warnings_count >= 0,
      do: warnings_count

  def warnings_count(%DB.MultiValidation{result: %{"warnings_count" => warnings_count}})
      when is_integer(warnings_count) and warnings_count >= 0,
      do: warnings_count

  def warnings_count(%DB.MultiValidation{validator: @gtfs_rt_validator_name}), do: 0
  def warnings_count(%DB.MultiValidation{}), do: nil

  def errors_count(%DB.MultiValidation{digest: %{"errors_count" => errors_count}})
      when is_integer(errors_count) and errors_count >= 0,
      do: errors_count

  def errors_count(%DB.MultiValidation{result: %{"errors_count" => errors_count}})
      when is_integer(errors_count) and errors_count >= 0,
      do: errors_count

  def errors_count(%DB.MultiValidation{}), do: nil

  def availability_number_days, do: 30
  def max_nb_history_resources, do: 25
  def days_notifications_sent, do: 90

  def availability_ratio_class(ratio) when ratio >= 0 and ratio <= 100 do
    cond do
      ratio >= 99 -> "resource__summary--Success"
      ratio >= 95 -> "resource__summary--Warning"
      true -> "resource__summary--Error"
    end
  end

  @doc """
  iex> outdated_class(~D[2025-12-28], ~D[2025-12-31])
  "resource__summary--Error"
  iex> outdated_class(~D[2026-01-15], ~D[2025-12-31])
  ""
  iex> outdated_class(~D[2025-12-01], ~D[2025-12-31])
  "resource__summary--Error"
  iex> outdated_class(~D[2025-12-25], ~D[2025-12-25])
  "resource__summary--Error"
  iex> outdated_class(~D[2025-12-26], ~D[2025-12-25])
  "resource__summary--Warning"
  """
  def outdated_class(%Date{} = end_date, reference_date \\ Date.utc_today()) do
    case Date.diff(end_date, reference_date) do
      diff when diff <= 0 -> "resource__summary--Error"
      diff when diff <= 7 -> "resource__summary--Warning"
      _ -> ""
    end
  end

  def validity_dates(assigns) do
    ~H"""
    <% start_date = get_validity_date(@multi_validation, "start_date") %>
    <% end_date = get_validity_date(@multi_validation, "end_date") %>
    <div :if={start_date && end_date} title={dgettext("page-dataset-details", "Validity period")}>
      <i class="icon icon--calendar-alt" aria-hidden="true"></i>
      <span>{Shared.DateTimeDisplay.format_date(start_date, @locale)}</span>
      <i class="icon icon--right-arrow ml-05-em" aria-hidden="true"></i>
      <% end_date_date = end_date |> Date.from_iso8601!() %>
      <span class={outdated_class(end_date_date)}>{Shared.DateTimeDisplay.format_date(end_date, @locale)}</span>
    </div>
    """
  end

  def get_validity_date(multi_validation, key) do
    multi_validation |> DB.MultiValidation.get_metadata_info(key) |> empty_to_nil()
  end

  def valid_panel_class(%DB.Resource{is_available: false}, _), do: "invalid-resource-panel"

  def valid_panel_class(%DB.Resource{} = r, is_outdated) do
    if Resource.gtfs?(r) && is_outdated do
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
      |> Enum.filter(&Resource.gtfs?/1)

  def unavailable_resources(dataset),
    do:
      dataset
      |> Dataset.official_resources()
      |> Enum.reject(fn r -> r.is_available end)

  def real_time_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.real_time?/1)

  def netex_official_resources(dataset),
    do:
      dataset
      |> official_available_resources()
      |> Enum.filter(&Resource.netex?/1)

  def schemas_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Enum.filter(&Resource.has_schema?/1)
    |> Enum.sort_by(& &1.display_position)
  end

  def other_official_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Stream.reject(&Resource.gtfs?/1)
    |> Stream.reject(&Resource.netex?/1)
    |> Stream.reject(&Resource.real_time?/1)
    |> Stream.reject(&Resource.documentation?/1)
    |> Stream.reject(&Resource.has_schema?/1)
    |> Enum.to_list()
    |> Enum.sort_by(& &1.display_position)
  end

  def official_documentation_resources(dataset) do
    dataset
    |> official_available_resources()
    |> Enum.filter(&Resource.documentation?/1)
  end

  def community_resources(dataset), do: Dataset.community_resources(dataset)

  def licence_url(licence) when licence in ["fr-lo", "lov2"],
    do: "https://www.etalab.gouv.fr/licence-ouverte-open-licence/"

  def licence_url("odc-odbl"), do: "https://opendatacommons.org/licenses/odbl/1.0/"

  def licence_url("mobility-licence"),
    do: "https://wiki.lafabriquedesmobilites.fr/wiki/Licence_Mobilités"

  def licence_url(_), do: nil

  @spec description(Dataset.t() | Resource.t()) :: Phoenix.HTML.safe()
  def description(%Dataset{description: description}), do: description |> markdown_to_safe_html!()
  def description(%Resource{description: description}), do: description |> markdown_to_safe_html!()

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
    |> Enum.reject(fn r -> Resource.community_resource?(r) or Resource.documentation?(r) end)
    |> Enum.max_by(&{&1.type, &1.last_update}, TransportWeb.DatasetView.ResourceTypeSortKey, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "vehicles-sharing", resources: resources}) do
    resources
    |> Enum.filter(fn r -> r.format == "gbfs" or String.ends_with?(r.url, "gbfs.json") end)
    |> Enum.reject(fn r ->
      String.contains?(r.url, "station_status") or String.contains?(r.url, "station_information") or
        Resource.community_resource?(r) or Resource.documentation?(r)
    end)
    |> Enum.max_by(& &1.last_update, DateTime, fn -> nil end)
  end

  def get_resource_to_display(%Dataset{type: "road-data", resources: resources}) do
    resources
    |> Enum.filter(fn r ->
      r.schema_name == "etalab/schema-zfe" or r.format == "geojson" or
        String.contains?(String.downcase(r.title), "geojson")
    end)
    # Display zones and not special roads
    |> Enum.reject(fn r ->
      String.contains?(r.url, "voie") or Resource.community_resource?(r) or Resource.documentation?(r)
    end)
    |> Enum.max_by(& &1.last_update, DateTime, fn -> nil end)
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
    Transport.Schemas.documentation_url(schema_name, schema_version)
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

  def resource_last_update_span(assigns) do
    assigns = assign(assigns, :real_time, Resource.real_time?(assigns.resource))

    ~H"""
    <span title={if @real_time, do: "", else: dgettext("page-dataset-details", "latest-content-modification-popover")}>
      <i class="icon icon--sync-alt" aria-hidden="true"></i>
      {resource_last_update_date_or_string(@resources_updated_at, @resource, @locale, real_time: @real_time)}
      <span :if={!@real_time} class="small">
        {dgettext("page-dataset-details", "latest-content-modification-label")}
      </span>
    </span>
    """
  end

  def resource_last_update_date_or_string(_resources_updated_at, _resource, _locale, real_time: true) do
    dgettext("page-dataset-details", "real-time")
  end

  def resource_last_update_date_or_string(resources_updated_at, %DB.Resource{id: id} = _resource, locale,
        real_time: false
      ) do
    resources_updated_at
    |> Map.get(id)
    |> case do
      nil -> dgettext("page-dataset-details", "unknown")
      dt -> dt |> DateTimeDisplay.format_datetime_to_date(locale)
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
  Determines if we should display OSM community guidelines for a dataset.

  ## Examples

  iex> display_odbl_osm_conditions?(%Dataset{licence: "odc-odbl", tags: ["foo"]})
  false
  iex> display_odbl_osm_conditions?(%Dataset{licence: "odc-odbl", tags: ["foo", "openstreetmap"], custom_tags: []})
  true
  iex> display_odbl_osm_conditions?(%Dataset{licence: "odc-odbl", tags: [], custom_tags: ["licence-osm"]})
  true
  iex> display_odbl_osm_conditions?(%Dataset{licence: "odc-odbl", tags: [], custom_tags: nil})
  false
  """
  def display_odbl_osm_conditions?(%Dataset{licence: "odc-odbl", tags: tags} = dataset) do
    "openstreetmap" in tags or Dataset.has_custom_tag?(dataset, "licence-osm")
  end

  def display_odbl_osm_conditions?(%Dataset{}), do: false

  @spec related_gtfs_resource(Resource.t()) :: DB.ResourceRelated.t() | nil
  def related_gtfs_resource(%Resource{format: "gtfs-rt", resources_related: resources_related}) do
    Enum.find(resources_related, fn %DB.ResourceRelated{reason: reason} -> reason == :gtfs_rt_gtfs end)
  end

  def related_gtfs_resource(%Resource{}), do: nil

  @doc """
  iex> seasonal_warning?(%DB.Dataset{dataset_subtypes: [%DB.DatasetSubtype{slug: "seasonal"}]})
  true
  iex> seasonal_warning?(%DB.Dataset{dataset_subtypes: [%DB.DatasetSubtype{slug: "urban"}]})
  false
  """
  def seasonal_warning?(%DB.Dataset{} = dataset), do: DB.Dataset.has_subtype?(dataset, "seasonal")

  def authentication_required?(%DB.Dataset{} = dataset),
    do: DB.Dataset.has_custom_tag?(dataset, "authentification_requise")

  @doc """
  iex> heart_class(%{42 => :producer}, %DB.Dataset{id: 42})
  "fa fa-heart producer"
  iex> heart_class(%{42 => nil}, %DB.Dataset{id: 42})
  "fa fa-heart"
  """
  def heart_class(dataset_heart_values, %DB.Dataset{id: dataset_id}) do
    value = dataset_heart_values |> Map.fetch!(dataset_id) |> to_string()
    "fa fa-heart #{value}" |> String.trim()
  end

  def latest_validation(%DB.Resource{id: resource_id} = resource, %{validations: validations} = _resources_infos) do
    validations = validations |> Map.get(resource_id)

    cond do
      Enum.count(validations) == 1 ->
        validations |> hd()

      # If the resource is GTFS and has multiple validations, give priority to the
      # MobilityData validator.
      DB.Resource.gtfs?(resource) and Enum.count(validations) == 2 ->
        validations |> Enum.filter(&Transport.Validators.MobilityDataGTFSValidator.mine?/1) |> hd()
    end
  end

  def empty_to_nil(""), do: nil
  def empty_to_nil(value), do: value

  def notification_sent(%{} = assigns) do
    ~H"""
    <tr>
      <td>{Transport.NotificationReason.reason_to_str(@notification.reason)}</td>
      <.notification_sent_details reason={@notification.reason} payload={@notification.payload} locale={@locale} />
      <td>{DateTimeDisplay.format_datetime_to_paris(@notification.timestamp, @locale)}</td>
    </tr>
    """
  end

  def notification_sent_details(
        %{
          reason: :resource_unavailable,
          payload: %{"resource_ids" => resource_ids, "hours_consecutive_downtime" => _}
        } = assigns
      ) do
    assigns =
      assign(
        assigns,
        :resources,
        DB.Resource |> where([r], r.id in ^resource_ids) |> Ecto.Query.select([r], [:title, :id]) |> DB.Repo.all()
      )

    ~H"""
    <td>
      <a :for={resource <- @resources} href={resource_path(TransportWeb.Endpoint, :details, resource.id)} target="_blank">
        {resource.title}
      </a>
      &mdash;&nbsp;{@payload["hours_consecutive_downtime"]}h
    </td>
    """
  end

  def notification_sent_details(%{reason: reason, payload: %{"resource_ids" => resource_ids}} = assigns)
      when reason in [:dataset_with_error, :resource_unavailable] do
    assigns =
      assign(
        assigns,
        :resources,
        DB.Resource |> where([r], r.id in ^resource_ids) |> Ecto.Query.select([r], [:title, :id]) |> DB.Repo.all()
      )

    ~H"""
    <td>
      <a :for={resource <- @resources} href={resource_path(TransportWeb.Endpoint, :details, resource.id)} target="_blank">
        {resource.title}
      </a>
    </td>
    """
  end

  def notification_sent_details(%{reason: :expiration} = assigns) do
    ~H"""
    <td>
      {Shared.DateTimeDisplay.relative_datetime_in_days(@payload["delay"], @locale)}
    </td>
    """
  end
end

defmodule TransportWeb.DatasetView.ResourceTypeSortKey do
  def compare({left_type, left_last_update}, {right_type, right_last_update}) do
    cond do
      left_type == right_type -> DateTime.compare(left_last_update, right_last_update)
      left_type == "main" -> :gt
      true -> :lt
    end
  end
end
