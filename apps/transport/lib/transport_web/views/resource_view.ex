defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  use Phoenix.Component
  import TransportWeb.PaginationHelpers
  import Phoenix.Controller, only: [current_url: 2]

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

  def netex_validation_report_title(
        %{level: _, max_severity: _, results_adapter: _, validation_report_url: _} = assigns
      ) do
    ~H"""
    <% %{"max_level" => max_level, "worst_occurrences" => worst_occurrences} = @max_severity %>
    <div class="header_with_action_bar">
      <.title level={@level}>
        {@results_adapter.format_severity(max_level, worst_occurrences) |> String.capitalize()}
      </.title>
      <.netex_validation_report_download validation_report_url={@validation_report_url} />
    </div>
    """
  end

  def netex_validation_report_title(%{validation_report_url: _} = assigns) do
    ~H"""
    <div class="header_with_action_bar">
      <h2>{dgettext("validations", "NeTEx review report")}</h2>
      <.netex_validation_report_download validation_report_url={@validation_report_url} />
    </div>
    """
  end

  defp title(%{level: 2} = assigns) do
    ~H"""
    <h2>{render_slot(@inner_block)}</h2>
    """
  end

  defp title(%{level: 4} = assigns) do
    ~H"""
    <h4>{render_slot(@inner_block)}</h4>
    """
  end

  def netex_validation_report_content(
        %{
          conn: _,
          current_category: _,
          issues: _,
          results_adapter: _,
          validation_report_url: _,
          validation_summary: _,
          xsd_errors: _,
          pagination: _
        } = assigns
      ) do
    ~H"""
    <% compliance_check = @results_adapter.french_profile_compliance_check() %>
    <% errors =
      if @current_category == "xsd-schema" do
        @xsd_errors
      else
        @issues
      end %>

    <.netex_validation_categories
      conn={@conn}
      results_adapter={@results_adapter}
      validation_summary={@validation_summary}
      current_category={@current_category}
    />

    <.netex_validation_selected_category
      conn={@conn}
      compliance_check={compliance_check}
      current_category={@current_category}
      errors={errors}
      validation_report_url={@validation_report_url}
      pagination={@pagination}
    />
    """
  end

  def netex_validation_categories(%{conn: _, results_adapter: _, validation_summary: _, current_category: _} = assigns) do
    ~H"""
    <div id="categories">
      <.netex_errors_category
        :for={%{"category" => category, "stats" => stats} <- sort_categories(@validation_summary)}
        conn={@conn}
        results_adapter={@results_adapter}
        category={category}
        current_category={@current_category}
        stats={stats}
      />
    </div>
    """
  end

  defp sort_categories(summary) do
    category_position = fn category ->
      case category do
        "xsd-schema" -> 1
        "base-rules" -> 2
        _ -> 3
      end
    end

    summary
    |> Enum.sort_by(fn %{"category" => category} -> {category_position.(category), category} end)
  end

  def netex_validation_selected_category(
        %{conn: _, compliance_check: _, current_category: _, errors: _, validation_report_url: _, pagination: _} =
          assigns
      ) do
    ~H"""
    <% locale = get_session(@conn, :locale) %>
    <div class="selected-category">
      <.netex_category_description category={@current_category} compliance_check={@compliance_check} conn={@conn} />
      <.netex_category_comment count={Enum.count(@errors)} category={@current_category} />

      <div :if={@current_category == "xsd-schema" and Enum.count(@errors) > 0} id="issues-list">
        <p>
          {dgettext(
            "validations-explanations",
            "Here is a summary of XSD validation errors. Full detail of those errors is available in the <a href=\"%{validation_report_url}\" target=\"_blank\">CSV report</a>. Those errors are produced by <a href=\"https://gnome.pages.gitlab.gnome.org/libxml2/xmllint.html\" target=\"_blank\">xmllint</a>.",
            validation_report_url: @validation_report_url
          )
          |> raw()}
        </p>
        <.non_translated_messages locale={locale} />
        <table class="table netex_xsd_schema">
          <tr>
            <th>{dgettext("validations-explanations", "Occurrences")}</th>
            <th>{dgettext("validations-explanations", "Message")}</th>
          </tr>

          <tr :for={xsd_error <- @errors} class="message">
            <td>{Helpers.format_number(xsd_error["counts"], locale: locale)}</td>
            <td lang="en">{xsd_error["message"]}</td>
          </tr>
        </table>
      </div>
      <div :if={@current_category != "xsd-schema" and Enum.count(@errors) > 0} id="issues-list">
        <.non_translated_messages locale={locale} />
        {render(netex_template(@current_category), issues: @errors, conn: @conn)}
        {@pagination}
      </div>
    </div>
    """
  end

  defp non_translated_messages(%{locale: _} = assigns) do
    ~H"""
    <p :if={@locale != "en"}>
      {dgettext("validations-explanations", "The following errors are only available in English.")}
    </p>
    """
  end

  def netex_validation_report_download(%{validation_report_url: _} = assigns) do
    ~H"""
    <button class="button-outline small secondary" popovertarget="download-popup">
      <.download_popup_title />
    </button>
    <dialog id="download-popup" popover class="panel">
      <div class="header_with_action_bar">
        <h5><.download_popup_title /></h5>
        <button popovertarget="download-popup" popovertargetaction="hide" class="small secondary">
          <i class="fa fa-close"></i>
        </button>
      </div>
      <.download_popup_content url={@validation_report_url} />
    </dialog>
    """
  end

  def download_popup_title(%{} = assigns) do
    ~H"""
    <i class="icon icon--download" aria-hidden="true"></i> {dgettext("validations", "Download the report")}
    """
  end

  def download_popup_content(%{url: nil} = assigns) do
    ~H"""
    <p>
      {dgettext("validations", "No validation error. No report to download.")}
    </p>
    """
  end

  def download_popup_content(%{url: _} = assigns) do
    ~H"""
    <div class="download-grid">
      <span>
        {dgettext("validations", "As a CSV file:")}
      </span>
      <.download_button url={@url} format="csv">
        validation.csv
      </.download_button>
      <span>
        {dgettext("validations", "As a Parquet file:")}
      </span>
      <.download_button url={@url} format="parquet">
        validation.parquet
      </.download_button>
    </div>
    <hr />
    <p>
      {dgettext(
        "validations",
        "Parquet is way more compact file format but it will require you to use some dedicated tooling."
      )}
    </p>
    <p>
      {dgettext("validations", "Learn more about it <a href=\"%{parquet_url}\" target=\"_blank\">here</a>.",
        parquet_url: "https://parquet.apache.org/"
      )
      |> raw()}
    </p>
    """
  end

  def download_button(%{url: _, format: _} = assigns) do
    ~H"""
    <a class="download-button" href={"#{@url}?format=#{@format}"} target="_blank">
      <button class="button-outline small secondary">
        <i class="icon icon--download" aria-hidden="true"></i> {render_slot(@inner_block)}
      </button>
    </a>
    """
  end

  def netex_category_tooltip(%{category: _, compliance_check: _} = assigns) do
    ~H"""
    <p :if={@category == "french-profile"}>
      <.info_icon /> {french_profile_comment(@compliance_check)}
    </p>
    """
  end

  def netex_category_tooltip(%{} = assigns) do
    ~H"""
    """
  end

  defp french_profile_comment(:none), do: dgettext("validations", "netex-french-profile-no-compliance") |> raw()
  defp french_profile_comment(:partial), do: dgettext("validations", "netex-french-profile-partial-compliance") |> raw()
  defp french_profile_comment(:good_enough), do: ""

  defp netex_errors_category(%{conn: _, category: _, stats: _, results_adapter: _, current_category: _} = assigns) do
    ~H"""
    <.link
      class={
        netex_errors_category_classnames(
          @category,
          @current_category,
          @stats["count"],
          @results_adapter.french_profile_compliance_check()
        )
      }
      href={netex_link_to_category(@conn, @category)}
    >
      <.validity_icon errors={@stats["count"]} />
      <span>
        <span class="category">
          {netex_category_label(@category)}
        </span>
        <.stats :if={@stats["count"] > 0} stats={@stats} results_adapter={@results_adapter} />
      </span>
    </.link>
    """
  end

  defp netex_link_to_category(conn, category) do
    query_params =
      drop_empty_query_params(%{"issues_category" => category, "token" => conn.params["token"]})

    conn
    |> current_url(query_params)
    |> to_netex_validation_report()
  end

  defp drop_empty_query_params(query_params) do
    Map.reject(query_params, fn {_, v} -> is_nil(v) end)
  end

  defp netex_errors_category_classnames(category, current_category, errors, compliance_check) do
    validity =
      if errors == 0 do
        ["valid"]
      else
        ["invalid"]
      end

    variant =
      if category == "french-profile" and compliance_check == :partial do
        ["striped"]
      else
        []
      end

    selected =
      if current_category == category do
        ["selected"]
      else
        []
      end

    Enum.join(["colorful"] ++ validity ++ variant ++ selected, " ")
  end

  def netex_category_description(%{category: _, compliance_check: _, conn: _} = assigns) do
    ~H"""
    <% url = netex_link_to_category(@conn, "french-profile") %>
    <% description = netex_category_description_html(@category, url) %>
    <p :if={description}>
      {raw(description)}
    </p>
    <.netex_category_tooltip category={@category} compliance_check={@compliance_check} />
    """
  end

  def netex_category_comment(%{count: _, category: _} = assigns) do
    ~H"""
    <.netex_category_hints :if={@count > 0} category={@category} />
    <p :if={@count == 0}>
      <i class="fa fa-check"></i>
      {dgettext("validations", "All rules of this category are respected.")}
    </p>
    """
  end

  defp netex_category_hints(%{category: _} = assigns) do
    ~H"""
    <p :if={netex_category_hints_html(@category)}>
      <.info_icon /> {netex_category_hints_html(@category) |> raw()}
    </p>
    """
  end

  defp stats(%{stats: _, results_adapter: _} = assigns) do
    ~H"""
    – {@results_adapter.format_severity(@stats["criticity"], @stats["count"])}
    """
  end

  def validity_icon(%{errors: errors} = assigns) when errors > 0 do
    ~H"""
    <i class="fa fa-xmark fa-lg"></i>
    """
  end

  def validity_icon(assigns) do
    ~H"""
    <i class="fa fa-check fa-lg"></i>
    """
  end

  def info_icon(assigns) do
    ~H"""
    <i class="fa fa-circle-info"></i>
    """
  end

  def netex_category_label("xsd-schema"), do: dgettext("validations", "XSD")
  def netex_category_label("french-profile"), do: dgettext("validations", "French profile")
  def netex_category_label("base-rules"), do: dgettext("validations", "Base rules")
  def netex_category_label(_), do: dgettext("validations", "Other errors")

  def netex_category_description_html("xsd-schema", category_french_profile),
    do: dgettext("validations", "xsd-schema-description", category_french_profile: category_french_profile)

  def netex_category_description_html("french-profile", _), do: dgettext("validations", "french-profile-description")
  def netex_category_description_html("base-rules", _), do: dgettext("validations", "base-rules-description")
  def netex_category_description_html(_, _), do: nil

  def netex_category_hints_html("xsd-schema"), do: dgettext("validations", "xsd-schema-hints")
  def netex_category_hints_html(_), do: nil

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

  defp to_netex_validation_report(url), do: url <> "#validation-report"

  def error_label(severity) do
    case severity do
      "ERROR" -> "❌ " <> dgettext("validations", "Errors")
      "WARNING" -> "⚠️ " <> dgettext("validations", "Warnings")
      "INFO" -> "ℹ️ " <> dgettext("validations", "Information")
    end
  end

  def markdown(text), do: TransportWeb.MarkdownHandler.markdown_to_safe_html!(text)
end
