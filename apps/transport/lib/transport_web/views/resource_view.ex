defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  import DB.Validation
  import Phoenix.Controller, only: [current_url: 2]
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

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

  @doc """
  Given a dataset, a ressource, and a format, get the community resources
  associated to the given resource, with the specified format
  """
  def get_associated_resource(
        %DB.Dataset{} = dataset,
        %DB.Resource{title: _title, url: url},
        format
      ) do
    dataset.resources
    |> Enum.find(fn r ->
      r.original_resource_url == url and
        r.is_community_resource and
        r.format == format
    end)
  end

  def get_associated_resource(_dataset, _resource, _format), do: nil

  @doc """
  Similar to get_associated_resource\3, but when the resources list has been preloaded
  (no dataset needed)
  """
  def get_associated_resource(%DB.Resource{title: _title, url: url, dataset: %{resources: resources}}, format) do
    resources
    |> Enum.find(fn r ->
      r.original_resource_url == url and
        r.is_community_resource and
        r.format == format
    end)
  end

  def get_associated_resource(_resource, _format), do: nil

  def has_associated_geojson(%{} = resources_related_files, resource_id) do
    resources_related_files
    |> Map.get(resource_id)
    |> get_associated_geojson()
    |> case do
      nil -> false
      _ -> true
    end
  end

  def has_associated_geojson(_, _), do: false

  def has_associated_netex(dataset, resource) do
    case get_associated_resource(dataset, resource, "NeTEx") do
      nil -> false
      _ -> true
    end
  end

  def get_associated_geojson(%{geojson: geojson_url}), do: geojson_url
  def get_associated_geojson(_), do: nil

  def get_associated_netex(resource) do
    get_associated_resource(resource, "NeTEx")
  end

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
      hours -> "#{hours} h #{rem(seconds, 3600) |> div(60) |> abs()} min"
    end
  end
end
