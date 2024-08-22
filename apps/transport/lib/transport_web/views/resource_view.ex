defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  use Phoenix.Component
  import TransportWeb.PaginationHelpers
  import Transport.Validators.GTFSTransport
  import Phoenix.Controller, only: [current_url: 2]
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  import TransportWeb.DatasetView,
    only: [documentation_url: 1, errors_count: 1, warnings_count: 1, multi_validation_performed?: 1, description: 1]

  import DB.ResourceUnavailability, only: [floor_float: 2]
  import Shared.DateTimeDisplay, only: [format_datetime_to_paris: 2]
  import Shared.Validation.TableSchemaValidator, only: [validata_web_url: 1]
  import Transport.GBFSUtils, only: [gbfs_validation_link: 1]
  import Transport.Shared.Schemas.Wrapper, only: [schema_type: 1]
  alias Shared.DateTimeDisplay
  def format_related_objects(nil), do: ""

  def format_related_objects(related_objects) do
    for %{"id" => id, "name" => name} <- related_objects, do: content_tag(:li, "#{name} (#{id})")
  end

  def issue_type([]), do: nil
  def issue_type([h | _]), do: h["issue_type"]

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
          "NegativeStopDuration" => "_negative_stop_duration_issue.html"
        },
        issue_type(issues.entries),
        "_generic_issue.html"
      )

    "_gtfs#{template}"
  end

  @spec action_path(Plug.Conn.t()) :: any
  def action_path(%Plug.Conn{params: %{"resource_id" => r_id} = params} = conn),
    do: resource_path(conn, :post_file, params["dataset_id"], r_id)

  def action_path(%Plug.Conn{params: params} = conn),
    do: resource_path(conn, :post_file, params["dataset_id"])

  def title(%Plug.Conn{params: %{"resource_id" => _}}),
    do: dgettext("resource", "Resource modification")

  def title(_), do: dgettext("resource", "Add a new resource")

  def remote?(%{"filetype" => "remote"}), do: true
  def remote?(_), do: false

  def link_to_datagouv_resource_edit(dataset_id, resource_id),
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/fr/admin/dataset/#{dataset_id}/resource/#{resource_id}")

  def link_to_datagouv_resource_creation(dataset_id),
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/fr/admin/dataset/#{dataset_id}?new_resource=")

  def dataset_creation,
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/fr/admin/dataset/new/")

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

  def get_associated_netex(%{NeTEx: netex_details}), do: netex_details
  def get_associated_netex(_), do: nil

  def errors_sample(%DB.MultiValidation{result: %{"errors" => errors}}) do
    Enum.take(errors, max_display_errors())
  end

  def max_display_errors, do: 50

  def hours_ago(utcdatetime) do
    DateTime.utc_now() |> DateTime.diff(utcdatetime) |> seconds_to_hours_minutes()
  end

  @doc """
  Converts seconds to a string showing hours and minutes.
  Also work for negative input, even if not intended to use it that way.

  iex> seconds_to_hours_minutes(3661)
  "1 h 1 min"
  iex> seconds_to_hours_minutes(60)
  "1 min"
  iex> seconds_to_hours_minutes(30)
  "0 min"
  iex> seconds_to_hours_minutes(-3661)
  "-1 h 1 min"
  """
  @spec seconds_to_hours_minutes(integer()) :: binary()
  def seconds_to_hours_minutes(seconds) do
    hours = div(seconds, 3600)

    case hours do
      0 -> "#{div(seconds, 60)} min"
      hours -> "#{hours} h #{seconds |> rem(3600) |> div(60) |> abs()} min"
    end
  end

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
end
