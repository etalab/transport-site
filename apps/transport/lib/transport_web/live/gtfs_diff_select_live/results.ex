defmodule TransportWeb.Live.GTFSDiffSelectLive.Results do
  @moduledoc """
  Results step of the GTFS diff tool.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext

  def results_step(
        %{
          diff_explanations: _,
          diff_file_url: _,
          diff_summary: _,
          error_msg: _,
          files_with_changes: _,
          gtfs_original_file_name_1: _,
          gtfs_original_file_name_2: _,
          selected_file: _
        } = assigns
      ) do
    ~H"""
    <div class="container gtfs-diff-results">
      <div :if={@diff_file_url} class="panel">
        <h4>
          <%= dgettext("validations", "GTFS Diff is available for") %>
          <%= link(dgettext("validations", "download"),
            to: @diff_file_url,
            target: "_blank"
          ) %>
        </h4>
        <%= raw(
          dgettext(
            "validations",
            "<a href=\"%{spec}\">Read</a> the GTFS Diff specification to understand how differences between GTFS are expressed",
            spec: "https://github.com/etalab/gtfs_diff/blob/main/specification.md"
          )
        ) %>.
        <%= if @diff_summary do %>
          <div class="pt-24">
            <%= if @diff_summary == %{} do %>
              <%= similar_files(@gtfs_original_file_name_1, @gtfs_original_file_name_2) %>
            <% else %>
              <%= different_files(@gtfs_original_file_name_1, @gtfs_original_file_name_2) %>
              <.diff_summaries
                diff_explanations={@diff_explanations}
                diff_summary={@diff_summary}
                files_with_changes={@files_with_changes}
                selected_file={@selected_file}
              />
            <% end %>
          </div>
        <% else %>
          <%= if @error_msg do %>
            <.validation_error error_msg={@error_msg} />
          <% else %>
            <div class="pt-24">
              <%= dgettext("validations", "analyzing found differences...") %>
            </div>
          <% end %>
        <% end %>
      </div>

      <button class="button primary" type="button" phx-click="start-over">
        <i class="fa fa-rotate-left"></i>&nbsp;<%= dgettext("validations", "Start over") %>
      </button>
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

  defp diff_summaries_for_file(%{selected_file: _, diff_summary: _} = assigns) do
    ~H"""
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
  end

  defp diff_summary_for_file(%{summary: _, selected_file: _, translation: _, class: _} = assigns) do
    ~H"""
    <div :if={@summary}>
      <%= for {{file, _nature, target}, n} <- @summary do %>
        <li :if={file == @selected_file}>
          <span class={@class}><%= @translation %> &nbsp;</span><%= translate_target(target, n) %>
        </li>
      <% end %>
    </div>
    """
  end

  defp diff_summaries(%{files_with_changes: _, selected_file: _, diff_summary: _, diff_explanations: _} = assigns) do
    ~H"""
    <div class="pt-24">
      <div class="dashboard">
        <.navigation files_with_changes={@files_with_changes} selected_file={@selected_file} />
        <.differencies diff_summary={@diff_summary} selected_file={@selected_file} diff_explanations={@diff_explanations} />
      </div>
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

  defp differencies(%{diff_summary: _, selected_file: _, diff_explanations: _} = assigns) do
    ~H"""
    <div class="main">
      <p><%= dgettext("validations", "Differences Overview") %></p>
      <.diff_summaries_for_file diff_summary={@diff_summary} selected_file={@selected_file} />
      <%= if assigns[:diff_explanations] do %>
        <% active_explanations =
          @diff_explanations
          |> Enum.filter(fn {file, _} -> file == @selected_file end)
          |> Enum.map(fn {_, explanation} -> explanation end) %>
        <p :if={not Enum.empty?(active_explanations)}><%= dgettext("validations", "Detail") %></p>
        <ul>
          <%= for explanation <- active_explanations do %>
            <li>
              <%= explanation %>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  defp similar_files(file1, file2) do
    dgettext(
      "validations",
      "The GTFS files <code>%{gtfs_original_file_name_2}</code> and <code>%{gtfs_original_file_name_1}</code> are similar.",
      gtfs_original_file_name_1: file1,
      gtfs_original_file_name_2: file2
    )
    |> raw()
  end

  defp different_files(file1, file2) do
    dgettext(
      "validations",
      "The GTFS file <code>%{gtfs_original_file_name_2}</code> has differences with the GTFS file <code>%{gtfs_original_file_name_1}</code>, as summarized below:",
      gtfs_original_file_name_1: file1,
      gtfs_original_file_name_2: file2
    )
    |> raw()
  end

  defp validation_error(%{error_msg: _} = assigns) do
    ~H"""
    <div class="pt-24">
      <%= dgettext(
        "validations",
        "An error occurred while interpreting the results. Note that the report is still available as download. Error:"
      ) %>
      <span class="red"><%= @error_msg %></span>
    </div>
    """
  end
end
