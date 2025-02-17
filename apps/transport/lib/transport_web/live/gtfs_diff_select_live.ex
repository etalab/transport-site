defmodule TransportWeb.Live.GTFSDiffSelectLive do
  @moduledoc """
  Beta functionality: generate GTFS file diffs online
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext
  alias TransportWeb.GTFSDiffExplain

  @max_file_size_mb 20

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> assign(:diff_logs, [])
     |> assign(:current_step, :setup)
     |> allow_upload(:gtfs,
       accept: ~w(.zip),
       max_entries: 2,
       max_file_size: @max_file_size_mb * 1_000_000,
       auto_upload: true
     )}
  end

  def handle_event("validate", _params, socket) do
    socket =
      socket
      |> assign(:diff_file_url, nil)
      |> assign(:error_msg, nil)
      |> assign(:diff_summary, nil)
      |> assign(:diff_explanations, nil)
      |> assign(:diff_logs, [])

    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :gtfs, ref)}
  end

  def handle_event("switch-uploads", _, socket) do
    {:noreply, update(socket, :uploads, &switch_uploads/1)}
  end

  def handle_event("start-over", _, socket) do
    {:noreply, clean_slate(socket)}
  end

  def handle_event("select-file", %{"file" => file}, socket) do
    {:noreply, assign(socket, :selected_file, file)}
  end

  def handle_event("gtfs_diff", _, socket) do
    send(self(), :enqueue_job)

    socket =
      socket
      |> assign(:job_running, true)
      |> assign(:current_step, :analysis)
      |> push_event("gtfs-diff-focus-steps", %{})

    {:noreply, socket}
  end

  def handle_info(:enqueue_job, socket) do
    [gtfs_file_name_2, gtfs_file_name_1] =
      consume_uploaded_entries(socket, :gtfs, fn %{path: path},
                                                 %Phoenix.LiveView.UploadEntry{client_name: original_file_name} ->
        file_name = Path.basename(path)
        stream_to_s3(path, file_name)
        {:ok, %{uploaded_file_name: file_name, original_file_name: original_file_name}}
      end)

    :ok = Oban.Notifier.listen([:gossip])

    %{id: job_id} =
      %{
        gtfs_file_name_1: gtfs_file_name_1.uploaded_file_name,
        gtfs_file_name_2: gtfs_file_name_2.uploaded_file_name,
        gtfs_original_file_name_1: gtfs_file_name_1.original_file_name,
        gtfs_original_file_name_2: gtfs_file_name_2.original_file_name,
        bucket: Transport.S3.bucket_name(:gtfs_diff),
        locale: Gettext.get_locale()
      }
      |> Transport.Jobs.GTFSDiff.new()
      |> Oban.insert!()

    socket =
      socket
      |> assign(:job_id, job_id)
      |> assign(:diff_logs, [dgettext("gtfs-diff", "Job started")])

    {:noreply, socket}
  end

  def handle_info({:generate_diff_summary, diff_file_url}, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    socket =
      case http_client.get(diff_file_url) do
        {:error, error} ->
          socket
          |> assign(:error_msg, HTTPoison.Error.message(error))

        {:ok, %{status_code: 200, body: body}} ->
          diff = Transport.GTFSDiff.parse_diff_output(body)

          diff_summary = diff |> GTFSDiffExplain.diff_summary()
          diff_explanations = diff |> GTFSDiffExplain.diff_explanations()

          files_with_changes =
            diff_summary
            |> Map.values()
            |> Enum.concat()
            |> Enum.map(fn {{file, _, _}, _} -> file end)
            |> Enum.sort()
            |> Enum.dedup()

          selected_file =
            case files_with_changes do
              [] -> nil
              _ -> Kernel.hd(files_with_changes)
            end

          socket
          |> assign(:diff_summary, diff_summary)
          |> assign(:diff_explanations, diff_explanations |> drop_empty())
          |> assign(:files_with_changes, files_with_changes)
          |> assign(:selected_file, selected_file)
      end

    {:noreply, socket}
  end

  # job has started
  def handle_info(
        {:notification, :gossip, %{"started" => job_id}},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    Process.send_after(self(), :timeout, Transport.Jobs.GTFSDiff.job_timeout_sec() * 1_000)
    {:noreply, socket}
  end

  # notifications about the ongoing job
  def handle_info(
        {:notification, :gossip, %{"running" => job_id, "log" => log}},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    {:noreply, socket |> assign(:diff_logs, [log | socket.assigns[:diff_logs]])}
  end

  # job is complete
  def handle_info(
        {:notification, :gossip,
         %{
           "complete" => job_id,
           "diff_file_url" => diff_file_url,
           "gtfs_original_file_name_1" => gtfs_original_file_name_1,
           "gtfs_original_file_name_2" => gtfs_original_file_name_2
         }},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    send(self(), {:generate_diff_summary, diff_file_url})
    Oban.Notifier.unlisten([:gossip])

    {:noreply,
     socket
     |> assign(:diff_file_url, diff_file_url)
     |> assign(:gtfs_original_file_name_1, gtfs_original_file_name_1)
     |> assign(:gtfs_original_file_name_2, gtfs_original_file_name_2)
     |> assign(:diff_logs, [])
     |> assign(:job_running, false)
     |> assign(:current_step, :results)
     |> push_event("gtfs-diff-focus-steps", %{})}
  end

  # job took too long
  def handle_info(:timeout, socket) do
    socket =
      if is_nil(socket.assigns[:diff_file_url]) do
        # no diff_file_url: job has not finished
        Oban.Notifier.unlisten([:gossip])

        socket
        |> assign(
          :error_msg,
          "Job aborted, the diff is taking too long (> #{Transport.Jobs.GTFSDiff.job_timeout_sec() / 60} min)."
        )
      else
        socket
      end

    {:noreply, socket}
  end

  # catch-all
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp stream_to_s3(file_path, path) do
    Transport.S3.stream_to_s3!(:gtfs_diff, file_path, path, acl: :public_read)
  end

  def uploads_are_valid(%{entries: gtfs}) do
    gtfs |> Enum.count() == 2 and gtfs |> Enum.all?(&(&1.valid? && &1.done?))
  end

  defp error_to_string(:too_large), do: "File is too large, must be <#{@max_file_size_mb}MB"
  defp error_to_string(:too_many_files), do: "You must select 2 files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

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

  defp switch_uploads(uploads) do
    Map.update!(uploads, :gtfs, fn gtfs ->
      Map.update!(gtfs, :entries, &Enum.reverse/1)
    end)
  end

  def step_completion(current_step, expected_step) do
    cond do
      step_progression(current_step) > step_progression(expected_step) -> "done"
      step_progression(current_step) == step_progression(expected_step) -> "active"
      true -> ""
    end
  end

  defp step_progression(step) do
    case step do
      :setup -> 1
      :analysis -> 2
      :results -> 3
    end
  end

  defp drop_empty([]), do: nil
  defp drop_empty(otherwise), do: otherwise

  defp clean_slate(socket) do
    socket
    |> assign(:current_step, :setup)
    |> assign(:diff_explanations, nil)
    |> assign(:diff_file_url, nil)
    |> assign(:diff_logs, [])
    |> assign(:diff_summary, nil)
    |> assign(:error_msg, nil)
    |> assign(:job_running, false)
    |> assign(:selected_file, nil)
    |> assign(:uploaded_files, [])
  end

  def steps(%{current_step: _} = assigns) do
    ~H"""
    <div id="gtfs-diff-steps" class="container">
      <ul class="steps-form">
        <li class={step_completion(@current_step, :setup)}>
          <div><%= dgettext("validations", "Setup") %></div>
        </li>
        <li class={step_completion(@current_step, :analysis)}>
          <div><%= dgettext("validations", "Analysis") %></div>
        </li>
        <li class={step_completion(@current_step, :results)}>
          <div><%= dgettext("validations", "Results") %></div>
        </li>
      </ul>
    </div>
    """
  end

  def preparation_step(%{uploads: _} = assigns) do
    ~H"""
    <div id="gtfs-diff-input" class="container" phx-drop-target={@uploads.ref}>
      <form id="upload-form" phx-submit="gtfs_diff" phx-change="validate">
        <.upload_drop_zone uploads={@uploads} />
        <.uploaded_files uploads={@uploads} />

        <button class="button" disabled={not uploads_are_valid(@uploads)} type="submit">
          <%= dgettext("validations", "Compare") %>
        </button>
      </form>
    </div>
    """
  end

  def upload_drop_zone(%{uploads: _} = assigns) do
    ~H"""
    <div class="drop-zone panel">
      <label for={@uploads.ref}>
        <i class="fa fa-upload" aria-hidden="true"></i>
        <span>
          <%= dgettext("validations", "Drop your GTFS files here or click to browse your local drive") %>
        </span>
      </label>
      <.live_file_input upload={@uploads} />
    </div>
    """
  end

  def uploaded_files(%{uploads: _} = assigns) do
    ~H"""
    <div id="uploaded-files">
      <%= for {entry, index} <- upload_entries(@uploads) do %>
        <.upload uploads={@uploads} entry={entry} index={index} />
        <%= if index == 0 do %>
          <.upload_switch uploads={@uploads} />
        <% end %>
      <% end %>
      <.upload_error :for={err <- upload_errors(@uploads)} error={err} />
    </div>
    """
  end

  def upload(%{entry: nil, index: _, uploads: _} = assigns) do
    ~H"""
    <article class="upload-entry upload-entry-inactive panel">
      <h4><%= upload_title(@index) %></h4>
      <label class="placeholder" for={@uploads.ref}>
        <%= dgettext("validations", "Please upload some file above") %>
      </label>
    </article>
    """
  end

  def upload(%{entry: entry, index: _, uploads: uploads} = assigns) do
    has_errors = length(upload_errors(uploads, entry)) > 0

    classname =
      if has_errors do
        "upload-entry upload-entry-errors panel"
      else
        "upload-entry panel"
      end

    assigns =
      assigns
      |> assign(:has_errors, has_errors)
      |> assign(:classname, classname)

    ~H"""
    <article class={@classname}>
      <h4><%= upload_title(@index) %></h4>
      <div class="entry-name">
        <%= if @entry.valid? do %>
          <.icon class="fa fa-square-check" title={dgettext("validations", "Valid file")} />
        <% else %>
          <.icon class="fa fa-square-xmark" title={dgettext("validations", "Invalid file")} />
        <% end %>
        <%= @entry.client_name %>
      </div>
      <div class="progress-bar">
        <progress value={@entry.progress} max="100"><%= @entry.progress %>%</progress>
        <button
          type="button"
          phx-click="cancel-upload"
          phx-value-ref={@entry.ref}
          title={dgettext("validations", "Cancel upload or remove file")}
          aria-label={dgettext("validations", "Cancel upload or remove file")}
        >
          <i class="fa fa-xmark"></i>
        </button>
      </div>
      <div :if={@has_errors} class="upload-errors">
        <%= for err <- upload_errors(@uploads, @entry) do %>
          <%= error_to_string(err) %>
        <% end %>
      </div>
    </article>
    """
  end

  def upload_error(%{error: _} = assigns) do
    ~H"""
    <p class="alert alert-danger"><i class="fa fa-square-xmark"></i> <%= error_to_string(@error) %></p>
    """
  end

  defp upload_title(index) do
    if index == 0 do
      dgettext("validations", "Reference GTFS")
    else
      dgettext("validations", "Modified GTFS")
    end
  end

  def upload_switch(%{uploads: _} = assigns) do
    ~H"""
    <div>
      <button
        disabled={length(@uploads.entries) != 2}
        class="button-outline primary small"
        type="button"
        title={dgettext("validations", "Switch files")}
        aria-label={dgettext("validations", "Switch files")}
        phx-click="switch-uploads"
      >
        <i class="fa fa-arrow-right-arrow-left"></i>
      </button>
    </div>
    """
  end

  defp icon(%{title: _, class: _} = assigns) do
    ~H"""
    <i class={@class} title={@title} aria-label={@title}></i>
    """
  end

  def upload_entries(uploads) do
    uploads.entries
    |> Enum.concat([nil, nil])
    |> Enum.take(2)
    |> Enum.with_index()
  end

  def diff_natures do
    [
      {"add", dgettext("validations", "added"), "green"},
      {"update", dgettext("validations", "updated"), "orange"},
      {"delete", dgettext("validations", "deleted"), "red"}
    ]
  end

  def diff_summaries_for_file(%{selected_file: _, diff_summary: _} = assigns) do
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

  def diff_summary_for_file(%{summary: _, selected_file: _, translation: _, class: _} = assigns) do
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

  def diff_summaries(%{files_with_changes: _, selected_file: _, diff_summary: _, diff_explanations: _} = assigns) do
    ~H"""
    <div class="pt-24">
      <div class="dashboard">
        <.navigation files_with_changes={@files_with_changes} selected_file={@selected_file} />
        <.differencies diff_summary={@diff_summary} selected_file={@selected_file} diff_explanations={@diff_explanations} />
      </div>
    </div>
    """
  end

  def navigation(%{files_with_changes: _, selected_file: _} = assigns) do
    ~H"""
    <aside class="side-menu" role="navigation">
      <ul>
        <.select_file_navigation_link :for={file <- @files_with_changes} file={file} selected_file={@selected_file} />
      </ul>
    </aside>
    """
  end

  def select_file_navigation_link(%{file: _, selected_file: _} = assigns) do
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

  def differencies(%{diff_summary: _, selected_file: _, diff_explanations: _} = assigns) do
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

  def similar_files(file1, file2) do
    dgettext(
      "validations",
      "The GTFS files <code>%{gtfs_original_file_name_2}</code> and <code>%{gtfs_original_file_name_1}</code> are similar.",
      gtfs_original_file_name_1: file1,
      gtfs_original_file_name_2: file2
    )
    |> raw()
  end

  def different_files(file1, file2) do
    dgettext(
      "validations",
      "The GTFS file <code>%{gtfs_original_file_name_2}</code> has differences with the GTFS file <code>%{gtfs_original_file_name_1}</code>, as summarized below:",
      gtfs_original_file_name_1: file1,
      gtfs_original_file_name_2: file2
    )
    |> raw()
  end

  def validation_error(%{error_msg: _} = assigns) do
    ~H"""
    <div class="pt-24">
      <%= dgettext(
        "validations",
        "An error occurred while interpreting the results. Note that the report is still available as download. Error:"
      ) %>
      <.error_message error_msg={@error_msg} />
    </div>
    """
  end

  def error_message(%{error_msg: _} = assigns) do
    ~H"""
    <span class="red"><%= @error_msg %></span>
    """
  end

  def analysis_step(%{diff_logs: _, error_msg: _} = assigns) do
    ~H"""
    <div class="container">
      <div class="panel">
        <h4><%= dgettext("validations", "Processing") %></h4>
        <%= for log <- Enum.reverse(@diff_logs) do %>
          <div>
            <%= raw(log) %>...
          </div>
        <% end %>
      </div>

      <div :if={@error_msg}>
        <.error_message error_msg={@error_msg} />
      </div>
    </div>
    """
  end
end
