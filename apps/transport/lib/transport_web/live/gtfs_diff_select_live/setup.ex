defmodule TransportWeb.Live.GTFSDiffSelectLive.Setup do
  @moduledoc """
  Setup step of the GTFS diff tool.
  """
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext
  use Phoenix.Component
  import TransportWeb.Live.GTFSDiffSelectLive.Shared

  def setup_step(%{uploads: _} = assigns) do
    ~H"""
    <div id="gtfs-diff-input" class="container" phx-drop-target={@uploads.ref}>
      <form id="upload-form" phx-submit="gtfs_diff" phx-change="validate">
        <.upload_drop_zone uploads={@uploads} />
        <.uploaded_files uploads={@uploads} />
        <.upload_global_error :for={err <- upload_errors(@uploads)} error={err} uploads={@uploads} />

        <.action_bar uploads={@uploads} />
      </form>
    </div>
    """
  end

  def action_bar(%{uploads: _} = assigns) do
    ~H"""
    <div class="actions">
      <button class="button" disabled={invalid_uploads?(@uploads)} type="submit">
        <i class="fa fa-check"></i>
        {dgettext("gtfs-diff", "Compare")}
      </button>
      <button
        type="button"
        class="button-outline primary"
        disabled={Enum.empty?(@uploads.entries)}
        phx-click="clear-uploads"
      >
        <i class="fa fa-trash"></i>
        {dgettext("gtfs-diff", "Clear uploaded files")}
      </button>
    </div>
    """
  end

  def invalid_uploads?(%{entries: gtfs}) do
    not (Enum.count(gtfs) == 2 and Enum.all?(gtfs, &(&1.valid? && &1.done?)))
  end

  defp upload_drop_zone(%{uploads: _} = assigns) do
    ~H"""
    <div class="drop-zone panel">
      <label for={@uploads.ref}>
        <i class="fa fa-upload" aria-hidden="true"></i>
        <span>
          {dgettext("gtfs-diff", "Drop your GTFS files here or click to browse your local drive")}
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
    </div>
    """
  end

  defp upload(%{entry: nil, index: _, uploads: _} = assigns) do
    ~H"""
    <article class="upload-entry upload-entry-inactive panel">
      <h4>{upload_title(@index)}</h4>
      <label class="placeholder" for={@uploads.ref}>
        {dgettext("gtfs-diff", "Please upload some file above")}
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
      <h4>{upload_title(@index)}</h4>
      <div class="entry-name">
        <%= if @entry.valid? do %>
          <.icon class="fa fa-square-check" title={dgettext("gtfs-diff", "Valid file")} />
        <% else %>
          <.icon class="fa fa-square-xmark" title={dgettext("gtfs-diff", "Invalid file")} />
        <% end %>
        {@entry.client_name}
      </div>
      <div class="progress-bar">
        <progress value={@entry.progress} max="100">{@entry.progress}%</progress>
        <button
          type="button"
          phx-click="cancel-upload"
          phx-value-ref={@entry.ref}
          title={dgettext("gtfs-diff", "Cancel upload or remove file")}
          aria-label={dgettext("gtfs-diff", "Cancel upload or remove file")}
        >
          <i class="fa fa-xmark"></i>
        </button>
      </div>
      <div :if={@has_errors} class="upload-errors">
        <%= for err <- upload_errors(@uploads, @entry) do %>
          {error_to_string(err)}
        <% end %>
      </div>
    </article>
    """
  end

  defp upload_global_error(%{error: _, uploads: _} = assigns) do
    ~H"""
    <p class="alert alert-danger">
      <i class="fa fa-square-xmark red"></i>
      {error_to_string(@error)}
      <.discarded_files :if={@error == :too_many_files} uploads={@uploads} />
    </p>
    """
  end

  defp discarded_files(%{uploads: _} = assigns) do
    ~H"""
    <span id="discarded-files">
      {dgettext("gtfs-diff", "Discarded files:")}
      <.discarded_file :for={{entry, index} <- Enum.with_index(@uploads.entries)} entry={entry} index={index} />.
    </span>
    """
  end

  defp discarded_file(%{entry: _, index: _} = assigns) do
    ~H"""
    <%= if @index > 0 do %>
      ,
    <% end %>
    <code class="discarded-file">{@entry.client_name}</code>
    """
  end

  @doc """
  iex> Gettext.put_locale("en")
  iex> error_to_string(:too_large)
  "File is too large, must be <20MB."
  iex> error_to_string(:too_many_files)
  "You must select 2 files."
  iex> error_to_string(:not_accepted)
  "You have selected an unacceptable file type."
  iex> Gettext.put_locale("fr")
  iex> error_to_string(:too_large)
  "Fichier trop gros, doit peser moins de 20 Mo."
  iex> error_to_string(:too_many_files)
  "Vous devez sélectionner 2 fichiers."
  iex> error_to_string(:not_accepted)
  "Le type de fichier sélectionné n’est pas utilisable."
  """
  def error_to_string(:too_many_files), do: dgettext("gtfs-diff", "You must select 2 files.")
  def error_to_string(:not_accepted), do: dgettext("gtfs-diff", "You have selected an unacceptable file type.")

  def error_to_string(:too_large),
    do:
      dgettext("gtfs-diff", "File is too large, must be <%{max_file_size_mb}MB.", max_file_size_mb: max_file_size_mb())

  defp upload_title(index) do
    if index == 0 do
      dgettext("gtfs-diff", "Reference GTFS")
    else
      dgettext("gtfs-diff", "Modified GTFS")
    end
  end

  defp upload_switch(%{uploads: _} = assigns) do
    ~H"""
    <div>
      <button
        disabled={length(@uploads.entries) != 2}
        class="button-outline primary small"
        type="button"
        title={dgettext("gtfs-diff", "Switch files")}
        aria-label={dgettext("gtfs-diff", "Switch files")}
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
    entries =
      if length(uploads.entries) > 2 do
        [nil, nil]
      else
        uploads.entries
        |> Enum.concat([nil, nil])
        |> Enum.take(2)
      end

    Enum.with_index(entries)
  end
end
