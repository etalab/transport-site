defmodule TransportWeb.NeTExReportComponents do
  @moduledoc """
  Set of components to display a NeTEx validation report. Those components are
  used by the resource details page and the on demand validation results page.
  """
  use TransportWeb, :view
  use Phoenix.Component
  import Phoenix.Controller, only: [current_url: 2]
  import Phoenix.HTML
  import Plug.Conn, only: [get_session: 2]
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.Components.ColorfulButton

  def to_netex_validation_report(url), do: url <> "#validation-report"

  def netex_generic_issues(%{issues: _} = assigns) do
    ~H"""
    <table class="table netex_generic_issue">
      <tr>
        <th>{dgettext("validations-explanations", "Message")}</th>
        <th>{dgettext("validations-explanations", "File")}</th>
        <th>{dgettext("validations-explanations", "Line")}</th>
      </tr>

      <tr :for={issue <- @issues} class="message">
        <td lang="en">{issue["message"]}</td>
        <%= if is_nil(issue["resource"]) or is_nil(issue["resource"]["filename"]) or is_nil(issue["resource"]["line"]) do %>
          <td colspan="2">{dgettext("validations-explanations", "Unknown location")}</td>
        <% else %>
          <td>{issue["resource"]["filename"]}</td>
          <td>{issue["resource"]["line"]}</td>
        <% end %>
      </tr>
    </table>
    """
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
      results_adapter={@results_adapter}
    />
    """
  end

  defp netex_validation_categories(%{conn: _, results_adapter: _, validation_summary: _, current_category: _} = assigns) do
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

  defp netex_validation_selected_category(
         %{
           conn: _,
           compliance_check: _,
           current_category: _,
           errors: _,
           validation_report_url: _,
           pagination: _,
           results_adapter: _
         } =
           assigns
       ) do
    ~H"""
    <% locale = get_session(@conn, :locale) %>
    <div class="selected-category">
      <.netex_category_description
        category={@current_category}
        compliance_check={@compliance_check}
        conn={@conn}
        results_adapter={@results_adapter}
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

  defp netex_validation_report_download(%{validation_report_url: _} = assigns) do
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

  defp download_popup_title(%{} = assigns) do
    ~H"""
    <i class="icon icon--download" aria-hidden="true"></i> {dgettext("validations", "Download the report")}
    """
  end

  defp download_popup_content(%{url: nil} = assigns) do
    ~H"""
    <p>
      {dgettext("validations", "No validation error. No report to download.")}
    </p>
    """
  end

  defp download_popup_content(%{url: _} = assigns) do
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

  defp download_button(%{url: _, format: _} = assigns) do
    ~H"""
    <a class="download-button" href={"#{@url}?format=#{@format}"} target="_blank">
      <button class="button-outline small secondary">
        <i class="icon icon--download" aria-hidden="true"></i> {render_slot(@inner_block)}
      </button>
    </a>
    """
  end

  defp with_string(proc) do
    {:ok, device} = StringIO.open("")

    proc.(device)

    StringIO.flush(device)
  end

  defp netex_category_tooltip(%{category: _, compliance_check: _, results_adapter: _, conn: _} = assigns) do
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
          <i class="fa fa-close"></i>
        </button>
      </div>
      <% markdown = with_string(&french_profile.markdown(&1, header_level: 6)) %>
      {markdown_to_safe_html!(markdown)}
    </dialog>
    """
  end

  defp netex_category_tooltip(%{} = assigns) do
    ~H"""
    """
  end

  defp markdown_to_safe_html!(markdown) do
    case TransportWeb.MarkdownHandler.markdown_to_safe_html!(markdown) do
      {:safe, safe} -> {:safe, update_links_target(safe)}
      otherwise -> otherwise
    end
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

  defp french_profile_comment(:none), do: dgettext("validations", "netex-french-profile-no-compliance") |> raw()
  defp french_profile_comment(:partial), do: dgettext("validations", "netex-french-profile-partial-compliance") |> raw()
  defp french_profile_comment(:good_enough), do: ""

  defp netex_errors_category(%{conn: _, category: _, stats: _, results_adapter: _, current_category: _} = assigns) do
    ~H"""
    <.colorful_link
      href={netex_link_to_category(@conn, @category)}
      valid={@stats["count"] == 0}
      selected={@current_category == @category}
    >
      <:icon>
        <.validity_icon errors={@stats["count"]} />
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

  defp netex_category_description(%{category: _, compliance_check: _, conn: _, results_adapter: _} = assigns) do
    ~H"""
    <% url = netex_link_to_category(@conn, "french-profile") %>
    <% description = netex_category_description_html(@category, url) %>
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

  defp netex_category_comment(%{count: _, category: _} = assigns) do
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

  defp validity_icon(%{errors: errors} = assigns) when errors > 0 do
    ~H"""
    <i class="fa fa-xmark fa-lg"></i>
    """
  end

  defp validity_icon(assigns) do
    ~H"""
    <i class="fa fa-check fa-lg"></i>
    """
  end

  defp info_icon(assigns) do
    ~H"""
    <i class="fa fa-circle-info"></i>
    """
  end

  defp netex_category_label("xsd-schema"), do: dgettext("validations", "XSD")
  defp netex_category_label("french-profile"), do: dgettext("validations", "French profile")
  defp netex_category_label("base-rules"), do: dgettext("validations", "Base rules")
  defp netex_category_label(_), do: dgettext("validations", "Other errors")

  defp netex_category_description_html("xsd-schema", category_french_profile),
    do: dgettext("validations", "xsd-schema-description", category_french_profile: category_french_profile)

  defp netex_category_description_html("french-profile", _), do: dgettext("validations", "french-profile-description")
  defp netex_category_description_html("base-rules", _), do: dgettext("validations", "base-rules-description")
  defp netex_category_description_html(_, _), do: nil

  defp netex_category_hints_html("xsd-schema"), do: dgettext("validations", "xsd-schema-hints")
  defp netex_category_hints_html(_), do: nil
end
