defmodule TransportWeb.Live.GTFSDiffSelectLive.Setup do
  @moduledoc """
  Setup step of the GTFS diff tool.
  """
  use Phoenix.LiveView
  import TransportWeb.Gettext

  @max_file_size_mb 20

  def setup_step(%{uploads: _} = assigns) do
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

  def uploads_are_valid(%{entries: gtfs}) do
    gtfs |> Enum.count() == 2 and gtfs |> Enum.all?(&(&1.valid? && &1.done?))
  end

  defp upload_drop_zone(%{uploads: _} = assigns) do
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

  defp uploaded_files(%{uploads: _} = assigns) do
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

  defp upload(%{entry: nil, index: _, uploads: _} = assigns) do
    ~H"""
    <article class="upload-entry upload-entry-inactive panel">
      <h4><%= upload_title(@index) %></h4>
      <label class="placeholder" for={@uploads.ref}>
        <%= dgettext("validations", "Please upload some file above") %>
      </label>
    </article>
    """
  end

  defp upload(%{entry: entry, index: _, uploads: uploads} = assigns) do
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

  defp upload_error(%{error: _} = assigns) do
    ~H"""
    <p class="alert alert-danger"><i class="fa fa-square-xmark"></i> <%= error_to_string(@error) %></p>
    """
  end

  defp error_to_string(:too_large), do: "File is too large, must be <#{@max_file_size_mb}MB"
  defp error_to_string(:too_many_files), do: "You must select 2 files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp upload_title(index) do
    if index == 0 do
      dgettext("validations", "Reference GTFS")
    else
      dgettext("validations", "Modified GTFS")
    end
  end

  defp upload_switch(%{uploads: _} = assigns) do
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

  defp upload_entries(uploads) do
    uploads.entries
    |> Enum.concat([nil, nil])
    |> Enum.take(2)
    |> Enum.with_index()
  end
end
