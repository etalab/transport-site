defmodule TransportWeb.Live.GTFSDiffSelectLive.Differences do
  @moduledoc """
  Differences of the selected file.
  """
  use Phoenix.Component
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.Live.GTFSDiffSelectLive.GTFSSpecification
  import TransportWeb.MarkdownHandler, only: [markdown_to_safe_html!: 1]

  def differences(
        %{diff_summary: _, selected_file: _, diff_explanations: _, profile: _, structural_changes: _} = assigns
      ) do
    ~H"""
    <div class="main">
      <.file_description selected_file={@selected_file} />
      <.structural_differences
        :if={Map.get(@structural_changes, @selected_file)}
        selected_file={@selected_file}
        structural_changes={Map.get(@structural_changes, @selected_file)}
      />
      <.diff_summaries_for_file diff_summary={@diff_summary} selected_file={@selected_file} profile={@profile} />
      <%= if assigns[:diff_explanations] do %>
        <% active_explanations =
          @diff_explanations
          |> Enum.filter(fn %{file: file} -> file == @selected_file end)
          |> Enum.group_by(fn %{type: type} -> type end)
          |> Map.to_list()
          |> Enum.filter(fn {_, explanations} -> not Enum.empty?(explanations) > 0 end) %>
        <%= if not Enum.empty?(active_explanations) do %>
          <h5><%= dgettext("gtfs-diff", "Notable changes:") %></h5>
          <.detailed_explanations
            :for={{explanation_type, explanations} <- active_explanations}
            file={@selected_file}
            explanations={explanations}
            explanation_type={explanation_type}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  defp structural_differences(%{structural_changes: structural_changes, selected_file: _} = assigns) do
    assigns =
      assigns
      |> assign(file_differences: Enum.filter(structural_changes, &file_difference?/1))
      |> assign(column_differences: Enum.filter(structural_changes, &column_difference?/1))

    ~H"""
    <.file_differences
      selected_file={@selected_file}
      file_differences={@file_differences}
      column_differences={@column_differences}
      file_criteria={:added_file}
      column_criteria={:added_columns}
    />
    <.file_differences
      selected_file={@selected_file}
      file_differences={@file_differences}
      column_differences={@column_differences}
      file_criteria={:deleted_file}
      column_criteria={:deleted_columns}
    />
    <.columns_differences
      selected_file={@selected_file}
      file_differences={@file_differences}
      column_differences={@column_differences}
      criteria={:added_columns}
    />
    <.columns_differences
      selected_file={@selected_file}
      file_differences={@file_differences}
      column_differences={@column_differences}
      criteria={:deleted_columns}
    />
    """
  end

  defp file_difference?(:added_file), do: true
  defp file_difference?(:deleted_file), do: true
  defp file_difference?(_), do: false

  defp file_differences(
         %{file_differences: _, column_differences: _, selected_file: _, file_criteria: _, column_criteria: _} = assigns
       ) do
    ~H"""
    <p :if={@file_differences == [@file_criteria]}>
      <i class={pick_symbol(@file_criteria)}></i>
      <%= pick_file_message(@file_criteria, count_column_differences(@column_differences, @column_criteria)) %>
    </p>
    <.columns_list
      :if={@file_differences == [@file_criteria]}
      selected_file={@selected_file}
      column_differences={Keyword.get(@column_differences, @column_criteria, [])}
    />
    """
  end

  defp pick_file_message(:added_file, 0), do: dgettext("gtfs-diff", "file added")

  defp pick_file_message(:added_file, count),
    do:
      dngettext(
        "gtfs-diff",
        "file added with %{count} new column:",
        "file added with %{count} new columns:",
        count
      )

  defp pick_file_message(:deleted_file, 0), do: dgettext("gtfs-diff", "file deleted")

  defp pick_file_message(:deleted_file, count),
    do:
      dngettext(
        "gtfs-diff",
        "file deleted along with %{count} column:",
        "file deleted along with %{count} columns:",
        count
      )

  defp column_difference?({:added_columns, _}), do: true
  defp column_difference?({:deleted_columns, _}), do: true
  defp column_difference?(_), do: false

  defp columns_differences(%{file_differences: _, column_differences: _, criteria: _, selected_file: _} = assigns) do
    assigns =
      assigns
      |> assign(relevant_column_differences: Keyword.get(assigns[:column_differences], assigns[:criteria], []))

    ~H"""
    <p :if={@file_differences == [] && @relevant_column_differences != []}>
      <i class={pick_symbol(@criteria)}></i>
      <%= pick_column_message(@criteria, Enum.count(@relevant_column_differences)) %>
    </p>
    <.columns_list
      :if={@file_differences == [] && @relevant_column_differences != []}
      selected_file={@selected_file}
      column_differences={@relevant_column_differences}
    />
    """
  end

  defp columns_list(%{column_differences: _, selected_file: _} = assigns) do
    ~H"""
    <ul>
      <li :for={column <- @column_differences}>
        <code><%= column %></code>
        <span :if={not standard_column?(@selected_file, column)}>
          <i class="symbol fa fa-warning orange"></i> <%= dgettext("gtfs-diff", "non standard column") %>
        </span>
      </li>
    </ul>
    """
  end

  defp count_column_differences(column_differences, criteria) do
    column_differences |> Keyword.get(criteria, []) |> Enum.count()
  end

  defp pick_column_message(:added_columns, count),
    do: dngettext("gtfs-diff", "Added %{count} column:", "Added %{count} columns:", count)

  defp pick_column_message(:deleted_columns, count),
    do: dngettext("gtfs-diff", "Deleted %{count} column:", "Deleted %{count} columns:", count)

  defp pick_symbol(:added_columns), do: "symbol fa fa-square-plus green"
  defp pick_symbol(:added_file), do: "symbol fa fa-square-plus green"
  defp pick_symbol(:deleted_columns), do: "symbol fa fa-square-minus red"
  defp pick_symbol(:deleted_file), do: "symbol fa fa-square-minus red"

  defp diff_summaries_for_file(%{selected_file: _, diff_summary: _, profile: _} = assigns) do
    cond do
      assigns[:selected_file] not in Transport.GTFSDiff.files_to_analyze(assigns[:profile]) ->
        ~H"""
        <p><%= dgettext("gtfs-diff", "Row changes:") %></p>
        <.partial_difference_warning />
        """

      row_changes?(assigns[:diff_summary], assigns[:selected_file]) ->
        ~H"""
        <p><%= dgettext("gtfs-diff", "Row changes:") %></p>
        <ul>
          <.diff_summary_for_file
            :for={{nature, translation, css_class} <- diff_natures()}
            summary={@diff_summary[nature]}
            translation={translation}
            selected_file={@selected_file}
            class={css_class}
          />
        </ul>
        """

      true ->
        ~H"""
        <p><%= dgettext("gtfs-diff", "No row changes.") %></p>
        """
    end
  end

  defp row_changes?(diff_summary, selected_file) do
    total_changes =
      diff_summary
      |> Map.values()
      |> Enum.concat()
      |> Enum.filter(fn {{file, _, target}, _} -> file == selected_file && target == "row" end)
      |> Enum.map(fn {_, c} -> c end)
      |> Enum.sum()

    total_changes > 0
  end

  defp diff_summary_for_file(%{summary: _, selected_file: _, translation: _, class: _} = assigns) do
    ~H"""
    <%= for {{file, _nature, target}, n} <- @summary || [] do %>
      <li :if={file == @selected_file && target == "row"}>
        <span class={@class}><%= @translation %></span>&nbsp;<%= translate_target(target, n) %>
      </li>
    <% end %>
    """
  end

  defp partial_difference_warning(%{} = assigns) do
    ~H"""
    <div class="notification warning">
      <%= dgettext(
        "gtfs-diff",
        "Row changes have not been analyzed for this file. We suggest you dive into both GTFS files for more details."
      ) %>
    </div>
    """
  end

  defp diff_natures do
    [
      {"add", dgettext("gtfs-diff", "added"), "green"},
      {"update", dgettext("gtfs-diff", "updated"), "orange"},
      {"delete", dgettext("gtfs-diff", "deleted"), "red"}
    ]
  end

  defp detailed_explanations(%{file: _, explanations: _, explanation_type: _} = assigns) do
    ~H"""
    <h6><%= translate_explanation_type(@file, @explanation_type) %> (<%= length(@explanations) %>)</h6>
    <p :if={translate_explanation_details(@file, @explanation_type)}>
      <%= translate_explanation_details(@file, @explanation_type) |> Enum.intersperse("\n\n") |> markdown_to_safe_html!() %>
    </p>
    <div class="scrollable-table">
      <table class="table">
        <thead>
          <tr>
            <th><%= dgettext("gtfs-diff", "Comment") %></th>
            <th><%= dgettext("gtfs-diff", "Original") %></th>
            <th><%= dgettext("gtfs-diff", "Modified") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={
            %{message: message, type: type_, before: before, after: after_} <-
              Enum.sort_by(@explanations, fn %{sort_key: sort_key} -> sort_key end)
          }>
            <td><%= message %></td>
            <td><.attribute_value type={attribute_type(@file, type_)} value={String.trim(before)} /></td>
            <td><.attribute_value type={attribute_type(@file, type_)} value={String.trim(after_)} /></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp attribute_type("routes.txt", "route_color"), do: :color
  defp attribute_type("routes.txt", "route_text_color"), do: :color
  defp attribute_type("routes.txt", "route_type"), do: :route_type
  defp attribute_type("stops.txt", "location_type"), do: :stop_location_type
  defp attribute_type(_, _), do: :text

  defp attribute_value(%{type: :color, value: "#"} = assigns) do
    ~H"""
    <em><%= dgettext("gtfs-diff", "no color") %></em>
    """
  end

  defp attribute_value(%{type: :color, value: _} = assigns) do
    ~H"""
    <div class="color-picker">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
        <rect x="0" y="0" width="16" height="16" stroke="black" stroke-width="2" fill={@value} />
      </svg>
      <%= @value %>
    </div>
    """
  end

  defp attribute_value(%{type: :route_type, value: _} = assigns) do
    ~H"""
    <%= @value %> (<%= route_type_short_description(@value) %>)
    """
  end

  defp attribute_value(%{type: :stop_location_type, value: _} = assigns) do
    ~H"""
    <%= @value %> (<%= stop_location_type_short_description(@value) %>)
    """
  end

  defp attribute_value(%{type: _, value: ""} = assigns) do
    ~H"""
    <em><%= dgettext("gtfs-diff", "no value") %></em>
    """
  end

  defp attribute_value(%{type: _, value: _} = assigns) do
    ~H"""
    <%= @value %>
    """
  end

  defp translate_explanation_type("stops.txt", "stop_name"), do: dgettext("gtfs-diff", "Stops' names")
  defp translate_explanation_type("stops.txt", "stop_position"), do: dgettext("gtfs-diff", "Stops' positions")
  defp translate_explanation_type("stops.txt", "wheelchair_boarding"), do: dgettext("gtfs-diff", "Weelchair boarding")
  defp translate_explanation_type("stops.txt", "location_type"), do: dgettext("gtfs-diff", "Location type")
  defp translate_explanation_type("routes.txt", "route_color"), do: dgettext("gtfs-diff", "Route color")
  defp translate_explanation_type("routes.txt", "route_text_color"), do: dgettext("gtfs-diff", "Route text color")
  defp translate_explanation_type("routes.txt", "route_short_name"), do: dgettext("gtfs-diff", "Route short name")
  defp translate_explanation_type("routes.txt", "route_long_name"), do: dgettext("gtfs-diff", "Route long name")
  defp translate_explanation_type("routes.txt", "route_type"), do: dgettext("gtfs-diff", "Route type")
  defp translate_explanation_type("agency.txt", "agency_url"), do: dgettext("gtfs-diff", "Agency URL")
  defp translate_explanation_type("trips.txt", "trip_headsign"), do: dgettext("gtfs-diff", "Trip headsign")
  defp translate_explanation_type(_, unknown), do: dgettext("gtfs-diff", "Other change: %{unknown}", unknown: unknown)

  defp translate_explanation_details("stops.txt", "stop_name"),
    do: [
      compared_attributes(["stop_name"]),
      dgettext(
        "gtfs-diff",
        "Name of the location. The `stop_name` should match the agency's rider-facing name for the location as printed on a timetable, published online, or represented on signage. For translations into other languages, use `translations.txt`."
      )
    ]

  defp translate_explanation_details("stops.txt", "stop_position"),
    do: [
      compared_attributes(["stop_lat", "stop_lon"]),
      dgettext(
        "gtfs-diff",
        "Computes the distance between locations. Results are sorted by distance. Moves shorter than 1 m are filtered out."
      )
    ]

  defp translate_explanation_details("stops.txt", "wheelchair_boarding"),
    do: [
      compared_attributes(["wheelchair_boarding"]),
      dgettext("gtfs-diff", "Indicates whether wheelchair boardings are possible from the location.")
    ]

  defp translate_explanation_details("stops.txt", "location_type"),
    do: [
      compared_attributes(["location_type"])
    ]

  defp translate_explanation_details("routes.txt", "route_color"),
    do: [
      compared_attributes(["route_color"]),
      dgettext(
        "gtfs-diff",
        "Route color designation that matches public facing material. Defaults to white (FFFFFF) when omitted or left empty. The color difference between `route_color` and `route_text_color` should provide sufficient contrast when viewed on a black and white screen."
      )
    ]

  defp translate_explanation_details("routes.txt", "route_text_color"),
    do: [
      compared_attributes(["route_text_color"]),
      dgettext(
        "gtfs-diff",
        "Legible color to use for text drawn against a background of `route_color`. Defaults to black (000000) when omitted or left empty."
      )
    ]

  defp translate_explanation_details("routes.txt", "route_short_name"),
    do: [
      compared_attributes(["route_short_name"]),
      dgettext(
        "gtfs-diff",
        "Short name of a route. Often a short, abstract identifier (e.g., \"32\", \"100X\", \"Green\") that riders use to identify a route."
      )
    ]

  defp translate_explanation_details("routes.txt", "route_long_name"),
    do: [
      compared_attributes(["route_long_name"]),
      dgettext(
        "gtfs-diff",
        "Full name of a route. This name is generally more descriptive than the `route_short_name` and often includes the route's destination or stop."
      )
    ]

  defp translate_explanation_details("routes.txt", "route_type"),
    do: [
      compared_attributes(["route_type"]),
      dgettext("gtfs-diff", "Indicates the type of transportation used on a route.")
    ]

  defp translate_explanation_details("agency.txt", "agency_url"),
    do: [
      compared_attributes(["agency_url"]),
      dgettext("gtfs-diff", "URL of the transit agency.")
    ]

  defp translate_explanation_details("trips.txt", "trip_headsign"),
    do: [
      compared_attributes(["trip_headsign"]),
      dgettext(
        "gtfs-diff",
        "Text that appears on signage identifying the trip's destination to riders. This field is recommended for all services with headsign text displayed on the vehicle which may be used to distinguish amongst trips in a route."
      )
    ]

  defp translate_explanation_details(_, _), do: nil

  defp compared_attributes(attributes) do
    introduction = dngettext("gtfs-diff", "Compare the value of ", "Compare the values of ", length(attributes))
    attributes = attributes |> Enum.map_intersperse(", ", fn attribute -> "`#{attribute}`" end)
    "#{introduction} #{attributes}."
  end

  @doc """
  iex> Gettext.put_locale("en")
  iex> translate_target("file", 1)
  "1 file"
  iex> translate_target("file", 3)
  "3 files"
  iex> translate_target("row", 1)
  "1 row"
  iex> translate_target("row", 3)
  "3 rows"
  iex> Gettext.put_locale("fr")
  iex> translate_target("file", 1)
  "1 fichier"
  iex> translate_target("file", 3)
  "3 fichiers"
  iex> translate_target("row", 1)
  "1 ligne"
  iex> translate_target("row", 3)
  "3 lignes"
  """
  def translate_target(target, n) do
    case target do
      "file" -> dngettext("gtfs-diff", "%{count} file", "%{count} files", n)
      "row" -> dngettext("gtfs-diff", "%{count} row", "%{count} rows", n)
      "column" -> dngettext("gtfs-diff", "%{count} column", "%{count} columns", n)
      _ -> "#{n} #{target}#{if n > 1, do: "s"}"
    end
  end
end
