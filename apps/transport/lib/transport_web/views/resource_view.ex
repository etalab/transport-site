defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  use Phoenix.Component
  import TransportWeb.PaginationHelpers
  import Phoenix.Controller, only: [current_url: 2]

  import TransportWeb.NeTExReportComponents,
    only: [
      netex_generic_issues: 1,
      netex_validation_report_content: 1,
      netex_validation_report_title: 1,
      to_netex_validation_report: 1
    ]

  import TransportWeb.DatasetView,
    only: [documentation_url: 1, errors_count: 1, warnings_count: 1, multi_validation_performed?: 1, description: 1]

  import DB.ResourceUnavailability, only: [floor_float: 2]
  import Shared.DateTimeDisplay, only: [format_datetime_to_paris: 2, format_duration: 2]
  import Transport.Validators.TableSchema, only: [validata_web_url: 1]
  import Transport.GBFSUtils, only: [gbfs_validation_link: 1]
  import Transport.Schemas.Wrapper, only: [schema_type: 1]
  alias Shared.DateTimeDisplay
  def format_related_objects(nil), do: ""

  def format_related_objects(related_objects) do
    for %{"id" => id, "name" => name} <- related_objects, do: content_tag(:li, "#{name} (#{id})")
  end

  def gtfs_template(issues) do
    template =
      Map.get(
        %{
          "UnloadableModel" => "_unloadable_model_issue.html",
          "DuplicateStops" => "_duplicate_stops_issue.html",
          "DuplicateStopSequence" => "_duplicate_stop_sequence_issue.html",
          "ExtraFile" => "_extra_file_issue.html",
          "MissingFile" => "_missing_file_issue.html",
          "NullDuration" => "_speed_issue.html",
          "ExcessiveSpeed" => "_speed_issue.html",
          "NegativeTravelTime" => "_speed_issue.html",
          "Slow" => "_speed_issue.html",
          "UnusedStop" => "_unused_stop_issue.html",
          "InvalidCoordinates" => "_coordinates_issue.html",
          "MissingCoordinates" => "_coordinates_issue.html",
          "UnusedShapeId" => "_unused_shape_issue.html",
          "InvalidShapeId" => "_invalid_shape_id_issue.html",
          "MissingId" => "_missing_id_issue.html",
          "MissingName" => "_missing_name_issue.html",
          "SubFolder" => "_subfolder_issue.html",
          "NegativeStopDuration" => "_negative_stop_duration_issue.html",
          "UnusableTrip" => "_unusable_trip.html",
          "NoCalendar" => "_no_calendar.html"
        },
        Transport.Validators.GTFSTransport.issue_type(issues.entries),
        "_generic_issue.html"
      )

    "_gtfs#{template}"
  end

  def netex_template(category \\ "") do
    template =
      Map.get(
        %{
          "xsd-schema" => "_xsd_schema.html"
        },
        category,
        "_generic_issue.html"
      )

    "_netex#{template}"
  end

  def get_associated_geojson(%{GeoJSON: geojson_details}), do: geojson_details
  def get_associated_geojson(_), do: nil

  def errors_sample(%DB.MultiValidation{result: %{"errors" => errors}}) do
    Enum.take(errors, max_display_errors())
  end

  def errors_sample(_), do: []

  def max_display_errors, do: 50

  def hours_ago(utcdatetime, locale) do
    DateTime.utc_now() |> DateTime.diff(utcdatetime) |> seconds_to_hours_minutes(locale)
  end

  @doc """
  Converts seconds to a string showing hours and minutes.
  Also work for negative input, even if not intended to use it that way.

  iex> seconds_to_hours_minutes(3661, :en)
  "1 hour and 1 minute"
  iex> seconds_to_hours_minutes(60, :en)
  "1 minute"
  iex> seconds_to_hours_minutes(30, :en)
  "0 minute"
  iex> seconds_to_hours_minutes(-3661, :en)
  "-1 hour and 1 minute"
  """
  @spec seconds_to_hours_minutes(integer(), atom() | Cldr.LanguageTag.t()) :: binary()
  def seconds_to_hours_minutes(seconds, locale \\ :en) do
    duration = strip_seconds(seconds)

    cond do
      duration == 0 -> "0 minute"
      duration < 0 -> "-#{Shared.DateTimeDisplay.format_duration(-duration, locale)}"
      true -> Shared.DateTimeDisplay.format_duration(duration, locale)
    end
  end

  def strip_seconds(seconds), do: div(seconds, 60) * 60

  def download_availability_class(ratio) when ratio >= 0 and ratio <= 100 do
    cond do
      ratio == 100 -> "download_availability_100"
      ratio >= 99 -> "download_availability_99"
      ratio >= 95 -> "download_availability_95"
      ratio >= 50 -> "download_availability_50"
      true -> "download_availability_low"
    end
  end

  def download_availability_class_text(ratio), do: download_availability_class(ratio) <> "_text"

  def gbfs_validator_url, do: "https://github.com/MobilityData/gbfs-validator"
  def gtfs_rt_validator_url, do: "https://github.com/MobilityData/gtfs-realtime-validator"
  def gtfs_validator_url, do: "https://github.com/etalab/transport-validator"
  def netex_validator_url, do: "https://documenter.getpostman.com/view/9950294/2sA3e2gVEE"

  def gtfs_rt_validator_rule_url(error_id) when is_binary(error_id) do
    gtfs_rt_validator_rule_url(%{"error_id" => error_id})
  end

  def gtfs_rt_validator_rule_url(%{"error_id" => error_id}) do
    "https://github.com/MobilityData/gtfs-realtime-validator/blob/master/RULES.md##{error_id}"
  end

  def mobilitydata_gtfs_validator_url, do: "https://gtfs-validator.mobilitydata.org"

  def on_demand_validation_link(conn, %DB.Resource{} = resource) do
    {tile, sub_tile} =
      cond do
        DB.Resource.gtfs?(resource) -> {"public-transit", "gtfs"}
        DB.Resource.gbfs?(resource) -> {"vehicles-sharing", "gbfs"}
        not is_nil(resource.schema_name) -> {"schemas", resource.schema_name}
        true -> ""
      end

    unless sub_tile == "" or TransportWeb.ValidationController.valid_type?(sub_tile) do
      raise "#{sub_tile} is not a valid type for on demand validation"
    end

    live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive,
      type: sub_tile,
      selected_tile: tile,
      selected_subtile: sub_tile
    )
  end

  @doc """
  iex> geojson_with_viz?(%DB.Resource{format: "geojson"}, %DB.ResourceHistory{payload: %{"permanent_url" => "https://example.com/file", "filesize" => 42}})
  true
  iex> geojson_with_viz?(%DB.Resource{format: "GTFS"}, %DB.ResourceHistory{payload: %{"permanent_url" => "https://example.com/file", "filesize" => 42}})
  false
  iex> geojson_with_viz?(%DB.Resource{format: "geojson"}, nil)
  false
  """
  def geojson_with_viz?(%DB.Resource{format: "geojson"}, %DB.ResourceHistory{
        payload: %{"permanent_url" => permanent_url, "filesize" => filesize}
      })
      when not is_nil(filesize) and not is_nil(permanent_url),
      do: true

  def geojson_with_viz?(_, _), do: false

  # credo:disable-for-next-line
  def service_alert_icon(%{cause: cause}) do
    case cause do
      :UNKNOWN_CAUSE -> "fa fa-question-circle"
      :OTHER_CAUSE -> "fa fa-question-circle"
      :TECHNICAL_PROBLEM -> "fa fa-exclamation-triangle"
      :STRIKE -> "fa fa-fist-raised"
      :DEMONSTRATION -> "fa fa-bullhorn"
      :ACCIDENT -> "fa fa-car-crash"
      :HOLIDAY -> "fa fa-calendar"
      :WEATHER -> "fa fa-cloud-rain"
      :MAINTENANCE -> "fa fa-wrench"
      :CONSTRUCTION -> "fa fa-hard-hat"
      :POLICE_ACTIVITY -> "fa fa-user-shield"
      :MEDICAL_EMERGENCY -> "fa fa-ambulance"
    end
  end

  # credo:disable-for-next-line
  def service_alert_effect(%{effect: effect}) do
    case effect do
      :NO_SERVICE -> dgettext("page-dataset-details", "No service")
      :REDUCED_SERVICE -> dgettext("page-dataset-details", "Reduced service")
      :SIGNIFICANT_DELAYS -> dgettext("page-dataset-details", "Significant delays")
      :DETOUR -> dgettext("page-dataset-details", "Detour")
      :ADDITIONAL_SERVICE -> dgettext("page-dataset-details", "Additional service")
      :MODIFIED_SERVICE -> dgettext("page-dataset-details", "Modified service")
      :OTHER_EFFECT -> dgettext("page-dataset-details", "Other effect")
      :UNKNOWN_EFFECT -> dgettext("page-dataset-details", "Unknown effect")
      :STOP_MOVED -> dgettext("page-dataset-details", "Stop moved")
      :NO_EFFECT -> dgettext("page-dataset-details", "No effect")
      :ACCESSIBILITY_ISSUE -> dgettext("page-dataset-details", "Accessibility issue")
    end
  end

  def nb_days_entities, do: Transport.Jobs.GTFSRTMetadataJob.days_to_keep()

  @spec display_gtfs_rt_feed(map()) :: binary()
  def display_gtfs_rt_feed(gtfs_rt_feed) do
    gtfs_rt_feed.feed
    |> Protobuf.JSON.encode!()
    |> Jason.Formatter.pretty_print()
  rescue
    _ -> dgettext("page-dataset-details", "Feed decoding failed")
  end

  @doc """
  iex> should_display_description?(%DB.Resource{description: nil})
  false
  iex> should_display_description?(%DB.Resource{description: "foo", title: nil})
  false
  iex> should_display_description?(%DB.Resource{description: nil, title: "Foo"})
  false
  iex> should_display_description?(%DB.Resource{description: "Bonjour", title: "Foo"})
  true
  """
  def should_display_description?(%DB.Resource{description: nil}), do: false
  def should_display_description?(%DB.Resource{title: nil}), do: false
  def should_display_description?(%DB.Resource{}), do: true

  def networks_start_end_dates(assigns) do
    end_date_class = fn end_date ->
      case Date.diff(end_date, Date.utc_today()) do
        n when n > 7 -> "valid"
        n when n > 0 -> "valid-not-for-long"
        _ -> "outdated"
      end
    end

    transform_data = fn networks_start_end_dates ->
      networks_start_end_dates
      |> Enum.into([])
      |> Enum.map(fn {network, %{"start_date" => start_date, "end_date" => end_date}} ->
        end_date = Date.from_iso8601!(end_date)

        {network,
         %{
           "start_date" => Date.from_iso8601!(start_date),
           "end_date" => end_date,
           "end_date_class" => end_date_class.(end_date)
         }}
      end)
      |> Enum.sort(fn {_, %{"end_date" => end_date_1}}, {_, %{"end_date" => end_date_2}} ->
        Date.compare(end_date_1, end_date_2) == :lt
      end)
    end

    assigns = Map.put(assigns, :network_data, transform_data.(assigns[:networks_start_end_dates]))

    ~H"""
    <div class="networks-start-end">
      <%= for {network, %{"start_date" => start_date, "end_date" => end_date, "end_date_class" => class}} <- @network_data do %>
        <span><strong>{network}</strong></span>
        <span>{dgettext("validations", "from")}</span>
        <span>{Shared.DateTimeDisplay.format_date(start_date, @locale)}</span>
        <span>{dgettext("validations", "to")}</span>
        <span class={class}>
          {Shared.DateTimeDisplay.format_date(end_date, @locale)}
        </span>
      <% end %>
    </div>
    """
  end

  def latest_validations_nb_days, do: 30

  def gtfs_for_gtfs_rt(
        %DB.Resource{format: "gtfs-rt", dataset: %DB.Dataset{resources: resources}},
        %DB.MultiValidation{secondary_resource_id: gtfs_id}
      ),
      do: Enum.find(resources, &(&1.id == gtfs_id))

  def gtfs_for_gtfs_rt(
        %DB.Resource{format: "gtfs-rt", dataset: %DB.Dataset{resources: resources}},
        nil = _multi_validation
      ) do
    gtfs_resources = resources |> Enum.filter(&DB.Resource.gtfs?/1)

    if Enum.count(gtfs_resources) == 1 do
      hd(gtfs_resources)
    else
      nil
    end
  end

  def format_nil_or_number(nil, _locale), do: ""
  def format_nil_or_number(value, locale), do: Helpers.format_number(value, locale: locale)

  def yes_no_icon(nil), do: ""
  def yes_no_icon(value) when value > 0, do: "✅"
  def yes_no_icon(_), do: "❌"

  def eligible_for_explore?(%DB.Resource{format: format}) do
    format in ["geojson", "csv", "ods", "xlsx", "xls"]
  end

  def explore_url(%DB.Resource{
        datagouv_id: resource_datagouv_id,
        dataset: %DB.Dataset{datagouv_id: dataset_datagouv_id}
      }) do
    "https://explore.data.gouv.fr/fr/datasets/#{dataset_datagouv_id}/#/resources/#{resource_datagouv_id}"
  end

  def netex_features(%{features: _} = assigns) do
    ~H"""
    <% features = enumerate_netex_features(@features) %>
    <li :if={not Enum.empty?(features)}>
      {dgettext("resource", "NeTEx features:")}
      {safe_join(features, ", ")}.
    </li>
    """
  end

  defp enumerate_netex_features(features) do
    features
    |> Enum.filter(fn {_feature, active} -> active end)
    |> Enum.sort_by(&feature_order/1)
    |> Enum.map(fn {feature, _} -> "<strong>#{netex_feature(feature)}</strong>" |> raw() end)
  end

  defp feature_order({"networks", _}), do: 1
  defp feature_order({"stops", _}), do: 2
  defp feature_order({"fares", _}), do: 3
  defp feature_order({"timetables", _}), do: 4
  defp feature_order({"parkings", _}), do: 5
  defp feature_order({"accessibility", _}), do: 6
  defp feature_order({_, _}), do: 100

  defp netex_feature("networks"), do: dgettext("resource", "networks")
  defp netex_feature("stops"), do: dgettext("resource", "stops")
  defp netex_feature("fares"), do: dgettext("resource", "fares")
  defp netex_feature("timetables"), do: dgettext("resource", "timetables")
  defp netex_feature("parkings"), do: dgettext("resource", "parkings")
  defp netex_feature("accessibility"), do: dgettext("resource", "accessibility")
  defp netex_feature(_), do: ""

  defp safe_join(safe_htmls, separator) do
    html =
      safe_htmls
      |> Enum.map_join(separator, fn {:safe, html} -> html end)

    {:safe, html}
  end

  def netex_statistics(%{stats: _, locale: _} = assigns) do
    ~H"""
    <.netex_statistic stats={@stats} locale={@locale} concept={:line} />
    <.netex_statistic stats={@stats} locale={@locale} concept={:quay} />
    <.netex_statistic stats={@stats} locale={@locale} concept={:stop_place} />
    """
  end

  defp netex_statistic(%{concept: _, stats: _, locale: _} = assigns) do
    ~H"""
    <% count = Map.get(@stats, "#{Atom.to_string(@concept)}s_count", 0) %>
    <li :if={count > 0} class="statistic">
      {netex_statistic_description(@concept)}
      <strong>{format_nil_or_number(count, @locale)}</strong>
      <.netex_statistic_element_tooltip concept={@concept} />
    </li>
    """
  end

  defp netex_statistic_description(:line), do: dgettext("resource", "number of lines:")
  defp netex_statistic_description(:quay), do: dgettext("resource", "number of quays:")
  defp netex_statistic_description(:stop_place), do: dgettext("resource", "number of stop places:")

  defp netex_statistic_element_tooltip(%{concept: _} = assigns) do
    ~H"""
    <span class="dropdown">
      <i class="fa fa-circle-question"></i>
      <div class="dropdown-content">
        {dgettext("resource", "Occurrences of the %{element} element.", element: netex_statistic_element(@concept))
        |> raw()}
      </div>
    </span>
    """
  end

  defp netex_statistic_element(:line), do: "Line" |> element()
  defp netex_statistic_element(:quay), do: "Quay" |> element()
  defp netex_statistic_element(:stop_place), do: "StopPlace" |> element()

  defp element(element_name) do
    "<code>&lt;#{element_name}&gt;</code>"
  end

  def netex_pagination_links(conn, issues, resource, current_category) do
    pagination_links(conn, issues, [resource.id],
      issues_category: current_category,
      path: &netex_issues_path/4,
      action: :details
    )
  end

  defp netex_issues_path(conn, action, resource_id, params) do
    resource_path(conn, action, resource_id, params) |> to_netex_validation_report()
  end

  def error_label(severity) do
    case severity do
      "ERROR" -> "❌ " <> dgettext("validations", "Errors")
      "WARNING" -> "⚠️ " <> dgettext("validations", "Warnings")
      "INFO" -> "ℹ️ " <> dgettext("validations", "Information")
    end
  end

  def markdown(text), do: TransportWeb.MarkdownHandler.markdown_to_safe_html!(text)
end
