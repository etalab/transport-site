defmodule TransportWeb.Live.GTFSDiffSelectLive.Results do
  @moduledoc """
  Results step of the GTFS diff tool.
  """
  use Phoenix.Component
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext
  import TransportWeb.Live.GTFSDiffSelectLive.GTFSSpecification

  def results_step(%{error_msg: _, profile: _, results: results} = assigns) do
    files_with_changes = files_with_changes(results[:diff_summary])

    assigns =
      assigns
      |> assign(files_with_changes: files_with_changes)
      |> assign(selected_file: results[:selected_file] || pick_selected_file(files_with_changes))

    ~H"""
    <.inner
      diff_explanations={@results[:diff_explanations]}
      diff_file_url={@results[:diff_file_url]}
      diff_summary={@results[:diff_summary]}
      structural_changes={@results[:structural_changes]}
      files_with_changes={@files_with_changes}
      context={@results[:context]}
      selected_file={@selected_file}
      error_msg={@error_msg}
      profile={@profile}
    />
    """
  end

  defp pick_selected_file([]), do: nil
  defp pick_selected_file(files_with_changes), do: Kernel.hd(files_with_changes)

  defp files_with_changes(nil), do: []

  defp files_with_changes(diff_summary) do
    diff_summary
    |> Map.values()
    |> Enum.concat()
    |> Enum.map(fn {{file, _, _}, _} -> file end)
    |> Enum.sort()
    |> Enum.dedup()
  end

  defp inner(
         %{
           diff_explanations: _,
           diff_file_url: _,
           diff_summary: _,
           error_msg: _,
           files_with_changes: _,
           context: _,
           profile: _,
           selected_file: _,
           structural_changes: _
         } = assigns
       ) do
    ~H"""
    <div id="gtfs-diff-results" class="container">
      <div :if={@diff_file_url} class="panel">
        <h4>
          <%= dgettext("validations", "GTFS Diff is available for") %>
          <%= link(dgettext("validations", "download"),
            to: @diff_file_url,
            target: "_blank"
          ) %>
        </h4>
        <p>
          <%= raw(
            dgettext(
              "validations",
              "<a href=\"%{spec}\">Read</a> the GTFS Diff specification to understand how differences between GTFS are expressed",
              spec: "https://github.com/MobilityData/gtfs_diff/blob/main/specification.md"
            )
          ) %>.
        </p>
        <%= if @diff_summary do %>
          <p><%= display_context(@diff_summary, @context) |> raw() %></p>
          <.diff_summaries
            :if={@diff_summary != %{}}
            diff_explanations={@diff_explanations}
            diff_summary={@diff_summary}
            files_with_changes={@files_with_changes}
            selected_file={@selected_file}
            structural_changes={@structural_changes}
            profile={@profile}
          />
        <% else %>
          <%= if @error_msg do %>
            <.validation_error error_msg={@error_msg} />
          <% else %>
            <p><%= dgettext("validations", "Analyzing found differences…") %></p>
          <% end %>
        <% end %>
      </div>

      <div class="actions">
        <button class="button-outline primary" type="button" phx-click="start-over">
          <i class="fa fa-rotate-left"></i>&nbsp;<%= dgettext("validations", "Start over") %>
        </button>
      </div>
    </div>
    """
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
      "file" -> dngettext("validations", "%{count} file", "%{count} files", n)
      "row" -> dngettext("validations", "%{count} row", "%{count} rows", n)
      "column" -> dngettext("validations", "%{count} column", "%{count} columns", n)
      _ -> "#{n} #{target}#{if n > 1, do: "s"}"
    end
  end

  defp diff_natures do
    [
      {"add", dgettext("validations", "added"), "green"},
      {"update", dgettext("validations", "updated"), "orange"},
      {"delete", dgettext("validations", "deleted"), "red"}
    ]
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
      column_differences={@column_differences}
      criteria={@column_criteria}
    />
    """
  end

  defp pick_file_message(:added_file, count),
    do:
      dngettext(
        "validations",
        "file added with %{count} new column:",
        "file added with %{count} new columns:",
        count
      )

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
    ~H"""
    <p :if={@file_differences == [] && Keyword.get(@column_differences, @criteria)}>
      <i class={pick_symbol(@criteria)}></i>
      <%= pick_column_message(@criteria, count_column_differences(@column_differences, @criteria)) %>
    </p>
    <.columns_list
      :if={@file_differences == [] && Keyword.get(@column_differences, @criteria)}
      selected_file={@selected_file}
      column_differences={@column_differences}
      criteria={@criteria}
    />
    """
  end

  defp columns_list(%{column_differences: _, criteria: _, selected_file: _} = assigns) do
    ~H"""
    <ul>
      <li :for={column <- Keyword.get(@column_differences, @criteria)}>
        <code><%= column %></code>
        <span :if={not standard_column?(@selected_file, column)}>
          <i class="symbol fa fa-warning orange"></i> <%= dgettext("validations", "non standard column") %>
        </span>
      </li>
    </ul>
    """
  end

  defp count_column_differences(column_differences, criteria) do
    column_differences |> Keyword.get(criteria) |> Enum.count()
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
    <.partial_difference_warning :if={@selected_file not in Transport.GTFSDiff.files_to_analyze(@profile)} />
    """
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

  defp diff_summaries(
         %{
           files_with_changes: _,
           selected_file: _,
           diff_summary: _,
           diff_explanations: _,
           profile: _,
           structural_changes: _
         } = assigns
       ) do
    ~H"""
    <div class="dashboard">
      <.navigation files_with_changes={@files_with_changes} selected_file={@selected_file} />
      <.differences
        diff_summary={@diff_summary}
        selected_file={@selected_file}
        diff_explanations={@diff_explanations}
        structural_changes={@structural_changes}
        profile={@profile}
      />
    </div>
    """
  end

  defp navigation(%{files_with_changes: _, selected_file: _} = assigns) do
    ~H"""
    <aside class="side-menu" role="navigation">
      <ul>
        <.select_file_navigation_link :for={file <- @files_with_changes} file={file} selected_file={@selected_file} />
      </ul>
    </aside>
    """
  end

  defp select_file_navigation_link(%{file: _, selected_file: _} = assigns) do
    assigns =
      assigns
      |> assign(
        :class,
        if assigns[:file] == assigns[:selected_file] do
          "active"
        end
      )

    ~H"""
    <li>
      <a class={@class} phx-click="select-file" phx-value-file={@file}>
        <code><%= @file %></code>
      </a>
    </li>
    """
  end

  defp differences(
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
          |> Enum.filter(fn {file, _} -> file == @selected_file end)
          |> Enum.map(fn {_, explanation} -> explanation end) %>
        <.detailed_explanations :if={not Enum.empty?(active_explanations)} active_explanations={active_explanations} />
      <% end %>
    </div>
    """
  end

  defp detailed_explanations(%{active_explanations: _} = assigns) do
    ~H"""
    <p>
      <%= dgettext("validations", "Notable changes:") %>
      <ul>
        <li :for={explanation <- @active_explanations}><%= explanation %></li>
      </ul>
    </p>
    """
  end

  defp display_context(diff_summary, %{
         "gtfs_original_file_name_1" => file_name_1,
         "gtfs_original_file_name_2" => file_name_2
       }) do
    if diff_summary == %{} do
      similar_files(file_name_1, file_name_2)
    else
      different_files(file_name_1, file_name_2)
    end
  end

  defp display_context(diff_summary, %{"gtfs_url_1" => url_1, "gtfs_url_2" => url_2}) do
    if diff_summary == %{} do
      similar_urls(url_1, url_2)
    else
      different_urls(url_1, url_2)
    end
  end

  defp similar_files(file_1, file_2) do
    dgettext(
      "validations",
      "The GTFS files <code>%{gtfs_original_file_name_2}</code> and <code>%{gtfs_original_file_name_1}</code> are similar.",
      gtfs_original_file_name_1: file_1,
      gtfs_original_file_name_2: file_2
    )
  end

  defp different_files(file_1, file_2) do
    dgettext(
      "validations",
      "The GTFS file <code>%{gtfs_original_file_name_2}</code> has differences with the GTFS file <code>%{gtfs_original_file_name_1}</code>, as summarized below:",
      gtfs_original_file_name_1: file_1,
      gtfs_original_file_name_2: file_2
    )
  end

  defp similar_urls(url_1, url_2) do
    dgettext(
      "validations",
      "The modified GTFS file (<a href=\"%{gtfs_url_2}\">source</a>) and the reference GTFS file (<a href=\"%{gtfs_url_1}\">source</a>) are similar.",
      gtfs_url_1: url_1,
      gtfs_url_2: url_2
    )
  end

  defp different_urls(url_1, url_2) do
    dgettext(
      "validations",
      "The modified GTFS file (<a href=\"%{gtfs_url_2}\">source</a>) has differences with the reference GTFS file (<a href=\"%{gtfs_url_1}\">source</a>), as summarized below:",
      gtfs_url_1: url_1,
      gtfs_url_2: url_2
    )
  end

  defp validation_error(%{error_msg: _} = assigns) do
    ~H"""
    <p>
      <%= dgettext(
        "validations",
        "An error occurred while interpreting the results. Note that the report is still available as download. Error:"
      ) %>
      <span class="red"><%= translate_error(@error_msg) %></span>.
    </p>
    """
  end

  defp translate_error(":enomem"), do: dgettext("validations", "not enough memory")
  defp translate_error(e), do: "#{e}"
end
