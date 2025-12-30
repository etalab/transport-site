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
  use TransportWeb.InputHelpers
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers

  @hide_file_upload_formats ["gbfs", "gtfs-rt"]
  @file_validation_enabled_formats ["GTFS", "NeTEx"]
  @url_validation_enabled_formats ["GTFS", "NeTEx"]

  @changeset_types %{
    title: :string,
    format: :string,
    url: :string
  }

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= form_for @changeset, @action_path, [multipart: true, as: :form, phx_change: "change"], fn f -> %>
      <%= text_input(f, :title,
        label: dgettext("espace-producteurs", "title"),
        placeholder: dgettext("espace-producteurs", "Example: Paris GTFS dataset"),
        required: true
      ) %>
      <%= select(f, :format, @formats, label: dgettext("espace-producteurs", "Format"), required: true) %>
      <div class="pt-24">
        <%= if @new_resource do %>
          <%= if file_validation_enabled?(changeset_value(@changeset, :format)) do %>
            <.interactive_validation_upload
              socket={@socket}
              locale={@locale}
              show_upload={@show_upload}
              uploads={@uploads}
              multi_validation={@multi_validation}
              uploaded_filename={@uploaded_filename}
              uploaded_path={@uploaded_path}
            />
          <% else %>
            <.upload_file :if={display_file_upload?(@changeset)} datagouv_resource={@datagouv_resource} f={f} />
          <% end %>
          <div :if={display_file_upload?(@changeset)} class="choose-or">
            - <%= dgettext("espace-producteurs", "or") %> -
          </div>
          <.specify_url
            datagouv_resource={@datagouv_resource}
            f={f}
            format={changeset_value(@changeset, :format)}
            url={changeset_value(@changeset, :url)}
            multi_validation={@multi_validation}
            locale={@locale}
            uploaded_filename={@uploaded_filename}
            socket={@socket}
          />
          <div class="choose-submit pt-24">
            <%= submit(dgettext("espace-producteurs", "Add the resource"), class: "button primary") %>
          </div>
        <% else %>
          <%= if TransportWeb.EspaceProducteurView.remote?(@datagouv_resource) do %>
            <.specify_url
              datagouv_resource={@datagouv_resource}
              f={f}
              format={changeset_value(@changeset, :format)}
              url={changeset_value(@changeset, :url)}
              multi_validation={@multi_validation}
              locale={@locale}
              uploaded_filename={@uploaded_filename}
              socket={@socket}
            />
          <% else %>
            <%= if file_validation_enabled?(changeset_value(@changeset, :format)) do %>
              <.interactive_validation_upload
                socket={@socket}
                locale={@locale}
                show_upload={@show_upload}
                uploads={@uploads}
                multi_validation={@multi_validation}
                uploaded_filename={@uploaded_filename}
                uploaded_path={@uploaded_path}
              />
            <% else %>
              <.upload_file :if={display_file_upload?(@changeset)} datagouv_resource={@datagouv_resource} f={f} />
            <% end %>
          <% end %>
          <div class="choose-submit pt-24">
            <%= submit(dgettext("espace-producteurs", "Update the resource"), class: "button primary") %>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp interactive_validation_upload(%{} = assigns) do
    ~H"""
    <div :if={@show_upload}>
      <div id="gtfs-diff-input" phx-drop-target={@uploads.zip.ref}>
        <div id="upload-form" class="pb-12" phx-change="validate">
          <.upload_drop_zone uploads={@uploads} />
        </div>
      </div>

      <section phx-drop-target={@uploads.zip.ref}>
        <article :for={entry <- @uploads.zip.entries} class="upload-entry">
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
    <.validation_report
      :if={@uploaded_filename}
      multi_validation={@multi_validation}
      locale={@locale}
      uploaded_filename={@uploaded_filename}
      socket={@socket}
    />
    <input :if={@uploaded_filename} type="hidden" name="resource_file[filename]" value={@uploaded_filename} />
    <input :if={@uploaded_path} type="hidden" name="resource_file[path]" value={@uploaded_path} />
    """
  end

  defp validation_report(%{} = assigns) do
    ~H"""
    <div :if={@multi_validation}>
      <p :if={@uploaded_filename}>
        <%= Phoenix.HTML.raw(dgettext("espace-producteurs", "File: <strong>%{name}</strong>", name: @uploaded_filename)) %>
      </p>
      <.validation_status multi_validation={@multi_validation} locale={@locale} />
      <a
        class="button-outline primary small mt-12"
        target="_blank"
        href={validation_path(@socket, :show, @multi_validation.id, token: @multi_validation.oban_args["secret_url_token"])}
      >
        <i class="icon fa fa-pen-to-square"></i><%= dgettext("espace-producteurs", "See the validation report") %>
      </a>
    </div>
    """
  end

  defp upload_file(%{f: _, datagouv_resource: _} = assigns) do
    ~H"""
    <div>
      <%= dgettext("espace-producteurs", "Upload a file") %>
      <%= unless is_nil(@datagouv_resource["url"]) do %>
        <p>
          <%= dgettext("espace-producteurs", "Current file: %{current_file}",
            current_file: Path.basename(@datagouv_resource["url"])
          ) %>
        </p>
      <% end %>
      <%= file_input(@f, :resource_file) %>
    </div>
    """
  end

  defp specify_url(%{} = assigns) do
    ~H"""
    <div>
      <%= dgettext("espace-producteurs", "Give a link for the resource") %>
      <%= text_input(
        @f,
        :url,
        placeholder: "https://data.ville.fr/gtfs.zip",
        type: "url"
      ) %>
    </div>
    <a
      :if={display_url_validation?(@format) and is_nil(@multi_validation) and valid_url?(@url)}
      class="button-outline primary small mt-12"
      phx-click="start-validation"
      phx-value-url={@url}
      phx-value-format={@format}
    >
      <i class="icon fa fa-check"></i><%= dgettext("espace-producteurs", "Start the validation") %>
    </a>
    <.validation_report
      :if={valid_url?(@url)}
      multi_validation={@multi_validation}
      locale={@locale}
      uploaded_filename={@uploaded_filename}
      socket={@socket}
    />
    """
  end

  defp upload_drop_zone(%{uploads: _} = assigns) do
    ~H"""
    <div class="drop-zone section-grey">
      <label for={@uploads.zip.ref}>
        <i class="fa fa-upload" aria-hidden="true"></i>
        <span>
          <%= dgettext("espace-producteurs", "Drop your file here or click to browse your local drive") %>
        </span>
      </label>
      <.live_file_input upload={@uploads.zip} />
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
    </p>
    <TransportWeb.DatasetView.validity_dates multi_validation={@multi_validation} locale={@locale} />
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
  def mount(
        _params,
        %{
          "locale" => locale,
          "action_path" => action_path,
          "datagouv_resource" => datagouv_resource,
          "new_resource" => new_resource,
          "resource" => resource,
          "formats" => formats
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(%{
       locale: locale,
       action_path: action_path,
       datagouv_resource: datagouv_resource,
       new_resource: new_resource,
       resource: resource,
       formats: formats,
       changeset: initialize_changeset(resource, formats)
     })
     |> reset_state()
     |> allow_upload(:zip, accept: ~w(.zip), max_entries: 1, auto_upload: true, progress: &handle_progress/3)}
  end

  defp initialize_changeset(%DB.Resource{} = resource, _formats) do
    Ecto.Changeset.cast({%{}, @changeset_types}, Map.from_struct(resource), Map.keys(@changeset_types))
  end

  defp initialize_changeset(_, formats) do
    Ecto.Changeset.cast({%{}, @changeset_types}, %{format: List.first(formats)}, Map.keys(@changeset_types))
  end

  defp reset_state(socket) do
    socket
    |> assign(:show_upload, true)
    |> assign(:multi_validation, nil)
    |> assign(:uploaded_filename, nil)
    |> assign(:uploaded_path, nil)
  end

  @impl Phoenix.LiveView
  def handle_event("change", %{"form" => form}, socket) do
    {:noreply,
     socket |> assign(:changeset, Ecto.Changeset.cast({%{}, @changeset_types}, form, Map.keys(@changeset_types)))}
  end

  def handle_event("start-validation", %{"url" => url, "format" => format}, socket) do
    multi_validation = create_multi_validation_for_url(url, format)
    dispatch_validation_job(multi_validation)
    schedule_next_update()
    {:noreply, socket |> assign(:multi_validation, multi_validation)}
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
    {:noreply, cancel_upload(socket, :zip, ref)}
  end

  defp handle_progress(:zip, entry, socket) do
    if entry.done? do
      [{multi_validation, path, client_name}] =
        consume_uploaded_entries(socket, :zip, fn %{path: path},
                                                  %Phoenix.LiveView.UploadEntry{client_name: client_name} ->
          filename = Ecto.UUID.generate()
          stream_to_s3(path, filename)

          multi_validation =
            create_multi_validation_for_file(filename, changeset_value(socket.assigns.changeset, :format))

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

  defp create_multi_validation_for_url(url, format) do
    filename = Path.basename(url)

    %DB.MultiValidation{
      validator: "on demand validation requested",
      validation_timestamp: DateTime.utc_now(),
      oban_args: %{
        "type" => String.downcase(format),
        "state" => "waiting",
        "filename" => filename,
        "permanent_url" => url,
        "secret_url_token" => Ecto.UUID.generate()
      },
      validated_data_name: filename
    }
    |> DB.Repo.insert!()
  end

  defp create_multi_validation_for_file(filename, format) do
    %DB.MultiValidation{
      validator: "on demand validation requested",
      validation_timestamp: DateTime.utc_now(),
      oban_args: %{
        "type" => String.downcase(format),
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

  defp changeset_value(changeset, field) do
    Ecto.Changeset.get_change(changeset, field)
  end

  defp file_validation_enabled?(format), do: format in @file_validation_enabled_formats
  defp display_url_validation?(format), do: format in @url_validation_enabled_formats

  defp display_file_upload?(changeset) do
    changeset_value(changeset, :format) not in @hide_file_upload_formats
  end

  def valid_url?(nil), do: false

  def valid_url?(string) do
    uri = URI.parse(string)
    uri.scheme in ["http", "https"] and uri.host != nil and String.contains?(uri.host, ".")
  end
end
