defmodule TransportWeb.Live.GTFSDiffSelectLive.Differences do
  @moduledoc """
  Differences of the selected file.
  """
  use Phoenix.Component
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.Live.GTFSDiffSelectLive.GTFSSpecification

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
          <h5><%= dgettext("validations", "Notable changes:") %></h5>
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

  defp pick_file_message(:added_file, 0), do: dgettext("validations", "file added")

  defp pick_file_message(:added_file, count),
    do:
      dngettext(
        "validations",
        "file added with %{count} new column:",
        "file added with %{count} new columns:",
        count
      )

  defp pick_file_message(:deleted_file, 0), do: dgettext("validations", "file deleted")

  defp pick_file_message(:deleted_file, count),
    do:
      dngettext(
        "validations",
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
          <i class="symbol fa fa-warning orange"></i> <%= dgettext("validations", "non standard column") %>
        </span>
      </li>
    </ul>
    """
  end

  defp count_column_differences(column_differences, criteria) do
    column_differences |> Keyword.get(criteria, []) |> Enum.count()
  end

  defp pick_column_message(:added_columns, count),
    do: dngettext("validations", "Added %{count} column:", "Added %{count} columns:", count)

  defp pick_column_message(:deleted_columns, count),
    do: dngettext("validations", "Deleted %{count} column:", "Deleted %{count} columns:", count)

  defp pick_symbol(:added_columns), do: "symbol fa fa-square-plus green"
  defp pick_symbol(:added_file), do: "symbol fa fa-square-plus green"
  defp pick_symbol(:deleted_columns), do: "symbol fa fa-square-minus red"
  defp pick_symbol(:deleted_file), do: "symbol fa fa-square-minus red"

  defp diff_summaries_for_file(%{selected_file: _, diff_summary: _, profile: _} = assigns) do
    cond do
      assigns[:selected_file] not in Transport.GTFSDiff.files_to_analyze(assigns[:profile]) ->
        ~H"""
        <p><%= dgettext("validations", "Row changes:") %></p>
        <.partial_difference_warning />
        """

      row_changes?(assigns[:diff_summary], assigns[:selected_file]) ->
        ~H"""
        <p><%= dgettext("validations", "Row changes:") %></p>
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
        <p><%= dgettext("validations", "No row changes.") %></p>
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
        "validations",
        "Row changes have not been analyzed for this file. We suggest you dive into both GTFS files for more details."
      ) %>
    </div>
    """
  end

  defp diff_natures do
    [
      {"add", dgettext("validations", "added"), "green"},
      {"update", dgettext("validations", "updated"), "orange"},
      {"delete", dgettext("validations", "deleted"), "red"}
    ]
  end

  defp detailed_explanations(%{file: _, explanations: _, explanation_type: _} = assigns) do
    ~H"""
    <h6><%= translate_explanation_type(@file, @explanation_type) %> (<%= length(@explanations) %>)</h6>
    <div class="scrollable-table">
      <table class="table">
        <thead>
          <tr>
            <th><%= dgettext("validations", "Comment") %></th>
            <th><%= dgettext("validations", "Original") %></th>
            <th><%= dgettext("validations", "Modified") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={
            %{message: message, before: before, after: after_} <-
              Enum.sort_by(@explanations, fn %{sort_key: sort_key} -> sort_key end)
          }>
            <td><%= message %></td>
            <td><%= before %></td>
            <td><%= after_ %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp translate_explanation_type("stops.txt", "stop_name"), do: dgettext("validations", "Stops' names")
  defp translate_explanation_type("stops.txt", "stop_position"), do: dgettext("validations", "Stops' positions")
  defp translate_explanation_type("stops.txt", "wheelchair_boarding"), do: dgettext("validations", "Weelchair boarding")
  defp translate_explanation_type(_, unknown), do: dgettext("validations", "Other change: %{unknown}", unknown: unknown)

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
      "file" -> dngettext("validations", "%{count} file", "%{count} files", n)
      "row" -> dngettext("validations", "%{count} row", "%{count} rows", n)
      "column" -> dngettext("validations", "%{count} column", "%{count} columns", n)
      _ -> "#{n} #{target}#{if n > 1, do: "s"}"
    end
  end
end
