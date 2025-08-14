defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  use Phoenix.Component
  import TransportWeb.PaginationHelpers
  import Phoenix.Controller, only: [current_url: 2]

  import TransportWeb.DatasetView,
    only: [documentation_url: 1, errors_count: 1, warnings_count: 1, multi_validation_performed?: 1, description: 1]

  import DB.ResourceUnavailability, only: [floor_float: 2]
  import Shared.DateTimeDisplay, only: [format_datetime_to_paris: 2, format_duration: 2]
  import Shared.Validation.TableSchemaValidator, only: [validata_web_url: 1]
  import Transport.GBFSUtils, only: [gbfs_validation_link: 1]
  import Transport.Shared.Schemas.Wrapper, only: [schema_type: 1]
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

  def has_associated_files(%{} = resources_related_files, resource_id) do
    # Don't keep records looking like `%{79088 => %{GeoJSON: nil, NeTEx: nil}}`
    resource_ids =
      resources_related_files
      |> Enum.reject(fn {_resource_id, conversions} ->
        conversions |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.empty?()
      end)
      |> Enum.map(fn {resource_id, _} -> resource_id end)

    resource_id in resource_ids
  end

  def has_associated_files(_, _), do: false

  def get_associated_geojson(%{GeoJSON: geojson_details}), do: geojson_details
  def get_associated_geojson(_), do: nil

  def errors_sample(%DB.MultiValidation{result: %{"errors" => errors}}) do
    Enum.take(errors, max_display_errors())
  end

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

  def on_demand_validation_link(conn, %DB.Resource{} = resource) do
    type =
      cond do
        DB.Resource.gtfs?(resource) -> "gtfs"
        DB.Resource.gbfs?(resource) -> "gbfs"
        not is_nil(resource.schema_name) -> resource.schema_name
        true -> ""
      end

    unless type == "" or TransportWeb.ValidationController.valid_type?(type) do
      raise "#{type} is not a valid type for on demand validation"
    end

    live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive, type: type)
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
        <span><strong><%= network %></strong></span>
        <span><%= dgettext("validations", "from") %></span>
        <span><%= Shared.DateTimeDisplay.format_date(start_date, @locale) %></span>
        <span><%= dgettext("validations", "to") %></span>
        <span class={class}>
          <%= Shared.DateTimeDisplay.format_date(end_date, @locale) %>
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

  def netex_validation_summary(%{conn: _, results_adapter: _, validation_summary: _, token: _} = assigns) do
    ~H"""
    <ul class="summary">
      <%= for {category, stats} <- @validation_summary do %>
        <.netex_errors_category
          conn={@conn}
          results_adapter={@results_adapter}
          category={category}
          stats={stats}
          token={@token}
        />
      <% end %>
    </ul>
    """
  end

  defp netex_errors_category(%{conn: _, category: _, stats: _, token: _, results_adapter: _} = assigns) do
    ~H"""
    <li>
      <.validity_icon errors={@stats[:count]} />
      <%= compatibility_filter(@conn, @category, @token) %>
      <%= if @stats[:count] > 0 do %>
        (<%= @results_adapter.format_severity(
          @stats[:criticity],
          @stats[:count]
        ) %>)
      <% end %>
    </li>
    <p :if={netex_category_description(@category) && @stats[:count] > 0}>
      <%= netex_category_description(@category) %>
    </p>
    """
  end

  defp compatibility_filter(conn, category, token) do
    query_params =
      %{"token" => token, "issues_category" => category}
      |> drop_empty_query_params()

    url = current_url(conn, query_params)

    category
    |> netex_category_label()
    |> link(class: "compatibility_filter", to: "#{url}#issues")
  end

  def validity_icon(%{errors: errors} = assigns) when errors > 0 do
    ~H"""
    <i class="fa fa-xmark"></i>
    """
  end

  def validity_icon(assigns) do
    ~H"""
    <i class="fa fa-check"></i>
    """
  end

  def netex_category_label("xsd-schema"), do: dgettext("validations", "XSD NeTEx")
  def netex_category_label(_), do: dgettext("validations", "Other errors")

  def netex_category_description("xsd-schema"), do: dgettext("validations", "xsd-schema-description") |> raw()
  def netex_category_description(_), do: nil

  defp drop_empty_query_params(query_params) do
    Map.reject(query_params, fn {_, v} -> is_nil(v) end)
  end
end
