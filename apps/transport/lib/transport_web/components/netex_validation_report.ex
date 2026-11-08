defmodule TransportWeb.NeTExValidationReportComponent do
  @moduledoc """
  Self-contained Phoenix Component for rendering a NeTEx validation report.

  Receives a `%NeTExValidationDetails{}` struct and `conn`, then renders the
  entire report section: title bar, category navigation, issues list, and
  pagination. Callers can wrap it with an `inner_block` slot for surrounding
  context (beta warnings, explanatory text, footer attribution).

  ## Usage

      <.netex_validation_report report={@report} conn={@conn}>
        <p>Beta warning goes here</p>
      </.netex_validation_report>
  """

  use TransportWeb, :html

  alias TransportWeb.Components.{ColorfulButton, Pagination}
  import Phoenix.Controller, only: [current_url: 2]
  import Plug.Conn, only: [get_session: 2]
  import ColorfulButton, only: [colorful_link: 1]
  import Pagination, only: [pagination: 1]

  attr(:report, :map, required: true, doc: "%NeTExValidationDetails{} struct")
  attr(:conn, Plug.Conn, required: true)

  slot(:inner_block, doc: "Surrounding context (beta warnings, explanatory text, etc.)")

  def netex_validation_report(%{report: %TransportWeb.NeTExValidationDetails{}, conn: _} = assigns) do
    ~H"""
    <div id="validation-report" class="validation-content">
      <%= if @inner_block do %>
        <div class="container">
          {render_slot(@inner_block)}
        </div>
      <% end %>

      <div class="container">
        <.netex_validation_report_title
          validation_report_url={@report.download_url}
          max_severity={@report.max_severity}
          results_adapter={@report.adapter}
        />

        <%= if @report.has_errors? do %>
          <div id="issues">
            <.netex_validation_report_content
              conn={@conn}
              current_category={@report.filter["issues_category"] || "xsd-schema"}
              xsd_errors={@report.xsd_errors}
              issues={@report.issues_page.entries}
              results_adapter={@report.adapter}
              validation_report_url={@report.download_url}
              validation_summary={@report.summary}
              pagination={
                netex_pagination_links(@conn, @report.issues_page, @report.filter["issues_category"] || "xsd-schema")
              }
              xsd_version={@report.metadata["xsd_version"]}
            />
          </div>
        <% else %>
          <div class="panel">
            <h2>{dgettext("validations", "Nice work, there are no issues!")}</h2>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Title section with severity formatting and download dialog
  @doc false
  attr(:validation_report_url, :string, required: true)
  attr(:max_severity, :map, default: nil)
  attr(:results_adapter, :any, default: nil)

  def netex_validation_report_title(%{results_adapter: nil, max_severity: nil} = assigns) do
    ~H"""
    <div class="header_with_action_bar">
      <h2>{dgettext("validations", "NeTEx review report")}</h2>
      <.netex_validation_report_download validation_report_url={@validation_report_url} />
    </div>
    """
  end

  def netex_validation_report_title(assigns) do
    ~H"""
    <% %{"max_level" => max_level, "worst_occurrences" => worst_occurrences} = @max_severity %>
    <div class="header_with_action_bar">
      <h2>{@results_adapter.format_severity(max_level, worst_occurrences) |> String.capitalize()}</h2>
      <.netex_validation_report_download validation_report_url={@validation_report_url} />
    </div>
    """
  end

  # Download dialog with CSV and Parquet options
  attr(:validation_report_url, :string, required: true)

  defp netex_validation_report_download(%{validation_report_url: _} = assigns) do
    ~H"""
    <button class="button-outline small secondary" popovertarget="download-popup">
      <i class="icon icon--download" aria-hidden="true"></i> {dgettext("validations", "Download the report")}
    </button>
    <dialog id="download-popup" popover class="panel">
      <div class="header_with_action_bar">
        <h5><i class="icon icon--download" aria-hidden="true"></i> {dgettext("validations", "Download the report")}</h5>
        <button popovertarget="download-popup" popovertargetaction="hide" class="small secondary">
          <i class="fa fa-xmark"></i>
        </button>
      </div>
      <.netex_download_popup_content url={@validation_report_url} />
    </dialog>
    """
  end

  @doc false
  def netex_download_popup_content(%{url: nil} = assigns) do
    ~H"""
    <p>
      {dgettext("validations", "No validation error. No report to download.")}
    </p>
    """
  end

  @doc false
  def netex_download_popup_content(assigns) do
    ~H"""
    <div class="download-grid">
      <span>{dgettext("validations", "As a CSV file:")}</span>
      <a class="download-button" href={"#{@url}?format=csv"} target="_blank">
        <button class="button-outline small secondary">
          <i class="icon icon--download" aria-hidden="true"></i> validation.csv
        </button>
      </a>
      <span>{dgettext("validations", "As a Parquet file:")}</span>
      <a class="download-button" href={"#{@url}?format=parquet"} target="_blank">
        <button class="button-outline small secondary">
          <i class="icon icon--download" aria-hidden="true"></i> validation.parquet
        </button>
      </a>
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

  # Category navigation, selected category view, and issues list
  attr(:conn, Plug.Conn, required: true)
  attr(:current_category, :string, required: true)
  attr(:issues, :list, required: true)
  attr(:results_adapter, :any, required: true)
  attr(:validation_report_url, :string, required: true)
  attr(:validation_summary, :list, required: true)
  attr(:xsd_errors, :list, required: true)
  attr(:pagination, :any, required: true)
  attr(:xsd_version, :string, default: nil)

  defp netex_validation_report_content(assigns) do
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
      results_adapter={@results_adapter}
      xsd_version={@xsd_version}
    />
    """
  end

  defp netex_validation_categories(assigns) do
    ~H"""
    <div id="categories">
      <.netex_errors_category
        :for={%{"category" => category, "stats" => stats} <- sort_categories(@validation_summary, @results_adapter)}
        conn={@conn}
        results_adapter={@results_adapter}
        category={category}
        current_category={@current_category}
        stats={stats}
      />
    </div>
    """
  end

  defp sort_categories(summary, results_adapter) do
    # v0_2.x summaries have %{"category" => ..., "stats" => ...}
    # v0_1.0 summaries have %{"severity" => ..., "issues" => ...}
    has_categories? = summary |> Enum.any?(&Map.has_key?(&1, "category"))

    if has_categories? do
      order = results_adapter.preferred_category_order()
      ordered_map = Enum.with_index(order) |> Map.new()

      summary
      |> Enum.sort_by(fn %{"category" => category} -> {Map.get(ordered_map, category, :infinity), category} end)
    else
      summary
    end
  end

  defp netex_validation_selected_category(assigns) do
    ~H"""
    <% locale = get_session(@conn, :locale) %>
    <div class="selected-category">
      <.netex_category_description
        category={@current_category}
        compliance_check={@compliance_check}
        conn={@conn}
        results_adapter={@results_adapter}
        xsd_version={@xsd_version}
      />
      <.netex_category_comment count={Enum.count(@errors)} category={@current_category} />

      <div :if={Enum.count(@errors) > 0} id="issues-list">
        <%= if @current_category == "xsd-schema" do %>
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
        <% else %>
          <.non_translated_messages locale={locale} />
          <.netex_generic_issues issues={@errors} />
          {@pagination}
        <% end %>
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

  # Category tab item
  attr(:conn, Plug.Conn, required: true)
  attr(:category, :string, required: true)
  attr(:stats, :map, required: true)
  attr(:results_adapter, :any, required: true)
  attr(:current_category, :string, required: true)

  defp netex_errors_category(assigns) do
    ~H"""
    <% variant = severity_variant(@stats["criticity"]) %>
    <.colorful_link
      href={netex_link_to_category(@conn, @category)}
      variant={variant}
      selected={@current_category == @category}
    >
      <:icon>
        <.validity_icon variant={variant} />
      </:icon>
      <:label>
        <span class="category">
          {netex_category_label(@category)}
        </span>
        <.stats :if={@stats["count"] > 0} stats={@stats} results_adapter={@results_adapter} />
      </:label>
    </.colorful_link>
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

  # Category description and tooltips
  attr(:category, :string, required: true)
  attr(:compliance_check, :any, required: true)
  attr(:conn, Plug.Conn, required: true)
  attr(:results_adapter, :any, required: true)
  attr(:xsd_version, :string, default: nil)

  defp netex_category_description(assigns) do
    ~H"""
    <% url = netex_link_to_category(@conn, "french-profile") %>
    <% description = netex_category_description_html(@category, url, @xsd_version) %>
    <p :if={description}>
      {raw(description)}
    </p>
    <.netex_category_tooltip
      category={@category}
      compliance_check={@compliance_check}
      results_adapter={@results_adapter}
      conn={@conn}
    />
    """
  end

  defp netex_category_comment(assigns) do
    ~H"""
    <.netex_category_hints :if={@count > 0} category={@category} />
    <p :if={@count == 0}>
      <i class="fa fa-check"></i>
      {dgettext("validations", "All rules of this category are respected.")}
    </p>
    """
  end

  defp netex_category_hints(assigns) do
    ~H"""
    <p :if={netex_category_hints_html(@category)}>
      <.info_icon /> {netex_category_hints_html(@category) |> raw()}
    </p>
    """
  end

  # French profile tooltip
  attr(:category, :string, required: true)
  attr(:compliance_check, :any, required: true)
  attr(:results_adapter, :any, required: true)
  attr(:conn, Plug.Conn, required: true)

  defp netex_category_tooltip(assigns) do
    ~H"""
    <% french_profile = @results_adapter.french_profile() %>
    <p :if={@category == "french-profile"}>
      <.info_icon /> {french_profile_comment(@compliance_check)}
      <button :if={french_profile} class="button-outline small secondary" popovertarget="french-profile-rules">
        <i class="fa fa-circle-question" aria-hidden="true"></i> {dgettext("validations", "Learn more")}
      </button>
    </p>
    <dialog :if={french_profile} id="french-profile-rules" popover class="panel inline-help">
      <div class="header_with_action_bar">
        <h5>{dgettext("validations", "List of French Profile rules currently checked")}</h5>
        <button popovertarget="french-profile-rules" popovertargetaction="hide" class="small secondary">
          <i class="fa fa-xmark"></i>
        </button>
      </div>
      <% markdown = with_string(&french_profile.markdown(&1, header_level: 6)) %>
      {markdown_to_safe_html!(markdown)}
    </dialog>
    """
  end

  # Issues table
  attr(:issues, :list, required: true)

  defp netex_generic_issues(assigns) do
    ~H"""
    <table class="table netex_generic_issue">
      <colgroup>
        <col class="message" />
        <col class="file" />
        <col class="line" />
      </colgroup>

      <tr>
        <th>{dgettext("validations-explanations", "Message")}</th>
        <th>{dgettext("validations-explanations", "File")}</th>
        <th>{dgettext("validations-explanations", "Line")}</th>
      </tr>

      <tr :for={issue <- @issues} class="message">
        <td class="message">
          <.validity_icon variant={severity_variant(issue["criticity"])} /> <span lang="en">{issue["message"]}</span>
        </td>
        <%= if unknown_location?(issue) do %>
          <td class="file" colspan="2">{dgettext("validations-explanations", "Unknown location")}</td>
        <% else %>
          <td class="file"><span class="text-wrapper">{issue["resource"]["filename"]}</span></td>
          <td class="line">{issue["resource"]["line"]}</td>
        <% end %>
      </tr>
    </table>
    """
  end

  defp unknown_location?(issue) do
    is_nil(issue["resource"]) or is_nil(issue["resource"]["filename"]) or is_nil(issue["resource"]["line"])
  end

  # Stats display in category tabs
  attr(:stats, :map, required: true)
  attr(:results_adapter, :any, required: true)

  defp stats(assigns) do
    ~H"""
    – {@results_adapter.format_severity(@stats["criticity"], @stats["count"])}
    """
  end

  # Severity icons and helpers
  defp validity_icon(%{variant: :error} = assigns) do
    ~H"""
    <i class="fa fa-xmark text-error" aria-label="Error"></i>
    """
  end

  defp validity_icon(%{variant: :warning} = assigns) do
    ~H"""
    <i class="fa fa-triangle-exclamation text-warning" aria-label="Warning"></i>
    """
  end

  defp validity_icon(%{variant: :information} = assigns) do
    ~H"""
    <i class="fa fa-circle-info text-info" aria-label="Information"></i>
    """
  end

  defp validity_icon(%{variant: :valid} = assigns) do
    ~H"""
    <i class="fa fa-check" aria-label="Valid"></i>
    """
  end

  defp info_icon(assigns) do
    ~H"""
    <i class="fa fa-circle-info" aria-label="Info"></i>
    """
  end

  defp severity_variant("error"), do: :error
  defp severity_variant("warning"), do: :warning
  defp severity_variant("information"), do: :information
  defp severity_variant(_), do: :valid

  defp netex_category_label("xsd-schema"), do: dgettext("validations", "XSD")
  defp netex_category_label("french-profile"), do: dgettext("validations", "French profile")
  defp netex_category_label("base-rules"), do: dgettext("validations", "Base rules")
  defp netex_category_label(_), do: dgettext("validations", "Other errors")

  defp netex_category_description_html("xsd-schema", category_french_profile, xsd_version) do
    base = dgettext("validations", "xsd-schema-description", category_french_profile: category_french_profile)

    if xsd_version do
      base <>
        " " <>
        dgettext("validations", "xsd-schema-version", version: xsd_version)
    else
      base
    end
  end

  defp netex_category_description_html("french-profile", _, _),
    do: dgettext("validations", "french-profile-description")

  defp netex_category_description_html("base-rules", _, _), do: dgettext("validations", "base-rules-description")
  defp netex_category_description_html(_, _, _), do: nil

  defp netex_category_hints_html("xsd-schema"), do: dgettext("validations", "xsd-schema-hints")
  defp netex_category_hints_html(_), do: nil

  defp french_profile_comment(:none), do: dgettext("validations", "netex-french-profile-no-compliance") |> raw()
  defp french_profile_comment(:partial), do: dgettext("validations", "netex-french-profile-partial-compliance") |> raw()
  defp french_profile_comment(:good_enough), do: ""

  defp to_netex_validation_report(url), do: url <> "#validation-report"

  defp with_string(proc) do
    {:ok, device} = StringIO.open("")

    proc.(device)

    StringIO.flush(device)
  end

  defp markdown_to_safe_html!(markdown) do
    {:safe, safe} = TransportWeb.MarkdownHandler.markdown_to_safe_html!(markdown)
    {:safe, update_links_target(safe)}
  end

  defp update_links_target(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(fn
      {"a", attrs, children} -> {"a", [{"target", "_blank"} | attrs], children}
      other -> other
    end)
    |> Floki.raw_html()
  end

  # Pagination helper — moved from duplicated view functions
  defp netex_pagination_links(conn, page, current_category) do
    assigns = %{conn: conn, page: page, current_category: current_category}

    ~H"""
    <.pagination conn={@conn} page={@page} params={[issues_category: @current_category]} anchor="validation-report" />
    """
  end
end
