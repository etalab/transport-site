defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  import DB.Validation
  import Phoenix.Controller, only: [current_url: 2]
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]
  import TransportWeb.DatasetView, only: [schema_url: 1, errors_count: 1, warnings_count: 1]
  import DB.Resource, only: [has_errors_details?: 1]
  import DB.ResourceUnavailability, only: [round_float: 2]
  import Shared.DateTimeDisplay, only: [format_datetime_to_paris: 2]
  alias Shared.DateTimeDisplay
  def format_related_objects(nil), do: ""

  def format_related_objects(related_objects) do
    for %{"id" => id, "name" => name} <- related_objects, do: content_tag(:li, "#{name} (#{id})")
  end

  def issue_type([]), do: nil
  def issue_type([h | _]), do: h["issue_type"]

  def template(issues) do
    Map.get(
      %{
        "UnloadableModel" => "_unloadable_model_issue.html",
        "DuplicateStops" => "_duplicate_stops_issue.html",
        "ExtraFile" => "_extra_file_issue.html",
        "MissingFile" => "_missing_file_issue.html",
        "NullDuration" => "_speed_issue.html",
        "ExcessiveSpeed" => "_speed_issue.html",
        "NegativeTravelTime" => "_speed_issue.html",
        "Slow" => "_speed_issue.html",
        "UnusedStop" => "_unused_stop_issue.html",
        "InvalidCoordinates" => "_coordinates_issue.html",
        "MissingCoordinates" => "_coordinates_issue.html"
      },
      issue_type(issues.entries),
      "_generic_issue.html"
    )
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

  def has_associated_file(%{} = resources_related_files, resource_id, get_associated_file) do
    resources_related_files
    |> Map.get(resource_id)
    |> get_associated_file.()
    |> case do
      nil -> false
      _ -> true
    end
  end

  def has_associated_file(_, _, _), do: false

  def has_associated_geojson(resources_related_files, resource_id) do
    has_associated_file(resources_related_files, resource_id, &get_associated_geojson/1)
  end

  def has_associated_netex(resources_related_files, resource_id) do
    has_associated_file(resources_related_files, resource_id, &get_associated_netex/1)
  end

  def get_associated_geojson(%{geojson: geojson_url}), do: geojson_url
  def get_associated_geojson(_), do: nil

  def get_associated_netex(%{netex: netex_url}), do: netex_url
  def get_associated_netex(_), do: nil

  def errors_sample(%DB.Resource{metadata: %{"validation" => %{"errors" => errors}}}) do
    Enum.take(errors, max_display_errors())
  end

  # GBFS resources do not have `errors` in the `validation` dict
  # in the metadata because we send people to an external
  # website to see errors.
  #
  # It would be better to have a shared model for validations.
  # See https://github.com/etalab/transport-site/issues/2047
  # See DB.Resource.has_errors_details?/1
  def errors_sample(%DB.Resource{format: "gbfs"}), do: []

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

  def gtfs_rt_validator_url, do: "https://github.com/CUTR-at-USF/gtfs-realtime-validator"

  def gtfs_rt_validator_rule_url(%{"error_id" => error_id}) do
    "https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/RULES.md##{error_id}"
  end

  def on_demand_validation_link(conn, %DB.Resource{} = resource) do
    type =
      cond do
        DB.Resource.is_gtfs?(resource) -> "gtfs"
        DB.Resource.is_gbfs?(resource) -> "gbfs"
        not is_nil(resource.schema_name) -> resource.schema_name
        true -> ""
      end

    unless type == "" or TransportWeb.ValidationController.is_valid_type?(type) do
      raise "#{type} is not a valid type for on demand validation"
    end

    live_path(conn, TransportWeb.Live.OnDemandValidationSelectLive, type: type)
  end

  def is_geojson_with_viz(%{format: "geojson"}, %{url: url, filesize: filesize})
      when not is_nil(filesize) and not is_nil(url),
      do: true

  def is_geojson_with_viz(_, _), do: false

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
    end
  end

  def nb_days_entities, do: Transport.Jobs.GTFSRTEntitiesJob.days_to_keep()
end
