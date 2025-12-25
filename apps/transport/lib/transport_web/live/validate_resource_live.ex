defmodule TransportWeb.Live.ValidateResourceLive do
  @moduledoc """
  A LiveView component for on-demand validation of GTFS files.

  This module provides an interactive interface for users to upload a `.zip` file,
  monitor its upload progress, and receive real-time feedback on its validity
  based on transit industry standards.

  ## Features

  * **Drag-and-Drop Upload**: Supports file selection via a styled drop zone using `Phoenix.LiveView.allow_upload/3`.
  * **Async Processing**: Upon successful upload, files are streamed to S3 and a background validation job (via Oban) is dispatched.
  * **Real-time Status Polling**: Uses `handle_info/2` to poll the database for updates on the `MultiValidation` state, switching from a loading spinner to a result report once completed.
  * **Validation Reporting**: Displays high-level status (Success/Error) and provides a link to a detailed validation report, including metadata like feed validity periods.

  ## Workflow

  1.  **Mount**: Initializes the upload configuration and resets the state.
  2.  **Upload**: User drops a file. `handle_progress/3` triggers once the upload is `done?`.
  3.  **Job Dispatch**: The file is stored on S3, a `DB.MultiValidation` record is created with a `waiting` state, and an `OnDemandValidationJob` is queued.
  4.  **Polling**: The view enters a polling loop (every 1 second) until the background job updates the state to `completed`.
  5.  **Result**: The UI displays the validation outcome. Users can click "Start again" to reset the process.

  ## Internal State

  * `@show_upload`: Boolean. Toggles between the upload form and the validation result/loader.
  * `@multi_validation`: The `%DB.MultiValidation{}` struct tracking the job status and errors.
  * `@uploaded_filename`: The original name of the client-side file.
  * `@uploaded_path`: The temporary path of the file on the server.
  """
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.Router.Helpers
  import TransportWeb.DatasetView, only: [outdated_class: 1, empty_to_nil: 1]

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div :if={@show_upload}>
      <div id="gtfs-diff-input" phx-drop-target={@uploads.gtfs.ref}>
        <form id="upload-form" class="pb-12" phx-change="validate">
          <.upload_drop_zone uploads={@uploads} />
        </form>
      </div>

      <section phx-drop-target={@uploads.gtfs.ref}>
        <article :for={entry <- @uploads.gtfs.entries} class="upload-entry">
          <div class="entry-name">
            <.icon :if={entry.valid?} class="fa fa-square-check" title={dgettext("gtfs-diff", "Valid file")} />
            <.icon :if={not entry.valid?} class="fa fa-square-xmark" title={dgettext("gtfs-diff", "Invalid file")} />
            <%= entry.client_name %>
          </div>
          <div class="progress-bar">
            <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>
            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              title={dgettext("gtfs-diff", "Cancel upload or remove file")}
              aria-label={dgettext("gtfs-diff", "Cancel upload or remove file")}
            >
              <i class="fa fa-xmark"></i>
            </button>
          </div>
        </article>
      </section>
    </div>
    <div :if={@multi_validation}>
      <p>
        <%= Phoenix.HTML.raw(dgettext("espace-producteurs", "File: <strong>%{name}</strong>", name: @uploaded_filename)) %>
      </p>
      <.validation_status multi_validation={@multi_validation} locale={@locale} />
      <a
        class="button-outline primary small"
        target="_blank"
        href={validation_path(@socket, :show, @multi_validation.id, token: @multi_validation.oban_args["secret_url_token"])}
      >
        <i class="icon fa fa-pen-to-square"></i><%= dgettext("espace-producteurs", "See the validation report") %>
      </a>
    </div>
    <input type="hidden" name="resource_file[filename]" value={@uploaded_filename} />
    <input type="hidden" name="resource_file[path]" value={@uploaded_path} />
    """
  end

  defp upload_drop_zone(%{uploads: _} = assigns) do
    ~H"""
    <div class="drop-zone section-grey">
      <label for={@uploads.gtfs.ref}>
        <i class="fa fa-upload" aria-hidden="true"></i>
        <span>
          <%= dgettext("espace-producteurs", "Drop your GTFS file here or click to browse your local drive") %>
        </span>
      </label>
      <.live_file_input upload={@uploads.gtfs} />
    </div>
    """
  end

  defp icon(%{title: _, class: _} = assigns) do
    ~H"""
    <i class={@class} title={@title} aria-label={@title}></i>
    """
  end

  defp validation_status(
         %{multi_validation: %DB.MultiValidation{oban_args: %{"state" => "completed"}, max_error: max_error}} = assigns
       )
       when max_error in ["Warning", "Information", "NoError"] do
    ~H"""
    <p class="notification success">
      <%= dgettext("espace-producteurs", "No errors") %>
      <% start_date = @multi_validation |> DB.MultiValidation.get_metadata_info("start_date") |> empty_to_nil() %>
      <% end_date = @multi_validation |> DB.MultiValidation.get_metadata_info("end_date") |> empty_to_nil() %>
      <% gtfs_outdated? = Transport.Validators.GTFSTransport.gtfs_outdated?(@multi_validation) %>
      <%= if start_date && end_date do %>
        <div title={dgettext("page-dataset-details", "Validity period")}>
          <i class="icon icon--calendar-alt" aria-hidden="true"></i>
          <span><%= start_date |> Shared.DateTimeDisplay.format_date(@locale) %></span>
          <i class="icon icon--right-arrow ml-05-em" aria-hidden="true"></i>
          <span class={outdated_class(gtfs_outdated?)}><%= end_date |> Shared.DateTimeDisplay.format_date(@locale) %></span>
        </div>
      <% end %>
    </p>
    """
  end

  defp validation_status(
         %{multi_validation: %DB.MultiValidation{oban_args: %{"state" => "completed"}, max_error: max_error}} = assigns
       )
       when max_error in ["Fatal", "Error"] do
    ~H"""
    <p class="notification error">
      <%= dgettext("espace-producteurs", "Invalid file") %>
    </p>
    <a phx-click="start_again" class="button-outline warning small mr-24">
      <i class="icon fa fa-rotate"></i>
      <%= dgettext("espace-producteurs", "Start again") %>
    </a>
    """
  end

  defp validation_status(%{} = assigns) do
    ~H"""
    <div class="loader_container">
      <div class="loader"></div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def mount(_params, %{"locale" => locale}, socket) do
    {:ok,
     socket
     |> assign(:locale, locale)
     |> reset_state()
     |> allow_upload(:gtfs, accept: ~w(.zip), max_entries: 1, auto_upload: true, progress: &handle_progress/3)}
  end

  defp reset_state(socket) do
    socket
    |> assign(:show_upload, true)
    |> assign(:multi_validation, nil)
    |> assign(:uploaded_filename, nil)
    |> assign(:uploaded_path, nil)
  end

  @impl Phoenix.LiveView
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("start_again", _params, socket) do
    {:noreply, socket |> reset_state()}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :gtfs, ref)}
  end

  defp handle_progress(:gtfs, entry, socket) do
    if entry.done? do
      [{multi_validation, path, client_name}] =
        consume_uploaded_entries(socket, :gtfs, fn %{path: path},
                                                   %Phoenix.LiveView.UploadEntry{client_name: client_name} ->
          filename = Ecto.UUID.generate()
          stream_to_s3(path, filename)

          multi_validation = create_multi_validation(filename)

          dispatch_validation_job(multi_validation)

          destination = System.tmp_dir!() <> filename
          File.cp!(path, destination)

          {:ok, {multi_validation, destination, client_name}}
        end)

      schedule_next_update()

      {:noreply,
       assign(socket, %{
         multi_validation: multi_validation,
         uploaded_path: path,
         uploaded_filename: client_name,
         show_upload: false
       })}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(:update_data, socket) do
    multi_validation = DB.Repo.reload!(socket.assigns.multi_validation) |> DB.Repo.preload(:metadata)

    if multi_validation.oban_args["state"] == "waiting" do
      schedule_next_update()
    end

    {:noreply, assign(socket, multi_validation: multi_validation)}
  end

  defp schedule_next_update do
    Process.send_after(self(), :update_data, 1_000)
  end

  defp create_multi_validation(filename) do
    %DB.MultiValidation{
      validator: "on demand validation requested",
      validation_timestamp: DateTime.utc_now(),
      oban_args: %{
        "type" => "gtfs",
        "state" => "waiting",
        "filename" => filename,
        "permanent_url" => Transport.S3.permanent_url(:on_demand_validation, filename),
        "secret_url_token" => Ecto.UUID.generate()
      },
      validated_data_name: filename
    }
    |> DB.Repo.insert!()
  end

  defp dispatch_validation_job(%DB.MultiValidation{id: id, oban_args: oban_args}) do
    oban_args |> Map.merge(%{"id" => id}) |> Transport.Jobs.OnDemandValidationJob.new() |> Oban.insert!()
  end

  defp stream_to_s3(local_filepath, path) do
    Transport.S3.stream_to_s3!(:on_demand_validation, local_filepath, path, acl: :public_read)
  end
end
