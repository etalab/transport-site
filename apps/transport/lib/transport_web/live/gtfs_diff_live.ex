defmodule TransportWeb.GTFSDiffLive do
  # use Phoenix.Component
  use Phoenix.LiveView, container: {:div, class: "gtfs-diff-selector"}
  alias Phoenix.PubSub
  alias TransportWeb.Router.Helpers, as: Routes

  def render(assigns) do
    ~H"""
    <div id="gtfs-diff-widget" class={show(@gtfs_files)} phx-hook="GTFSDiff">
      <strong>Comparer 2 GTFS</strong>
      <form phx-change="manual_input">
        <%= for i <- 0..1 do %>
          <% url = Enum.at(@gtfs_files, i) |> Map.get("url") || "" %>
          <div class="gtfs-diff-url pt-6">
            <input type="text" value={url} name={"url#{i+1}"} id={"url#{i+1}"} placeholder="url" />
            <%= if url != "" do %>
              <i class="icon icon--trash" phx-click="delete_url" phx-value-index={i} aria-hidden="true"></i>
            <% end %>
          </div>
        <% end %>
      </form>
      <%= if is_nil(@gtfs_diff_id) and not Enum.any?(@gtfs_files, &is_nil/1) do %>
        <button class="button-outline mt-12" phx-click="compare"><strong>Comparer</strong></button>
      <% end %>
      <%= if @job_executing do %>
        <i class="icon icon--spinner" aria-hidden="true"></i>
      <% end %>
      <%= if @gtfs_diff_id do %>
        <div class="mt-12">
          <.link navigate={Routes.gtfs_diff_path(@socket, :show, @gtfs_diff_id)} target="_blank" id="see-diff">
            <strong>Voir la différence</strong>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  def mount(_params, %{"page_id" => page_id}, socket) do
    if connected?(socket) do
      PubSub.subscribe(TransportWeb.PubSub, "diff")
      :ok = Oban.Notifier.listen([:gossip])
    end

    socket =
      socket
      |> assign(:gtfs_files, [%{}, %{}])
      |> assign(:job_executing, false)
      |> assign(:gtfs_diff_id, nil)
      |> assign(:page_id, page_id)

    socket =
      if connected?(socket) do
        socket |> push_event("restore", %{key: "cle"})
      else
        socket
      end

    {:ok, socket}
  end

  def handle_info({"add_url", %{"url" => _url} = gtfs_file, page_id}, socket)
      when page_id == socket.assigns.page_id do
    gtfs_files =
      case socket.assigns.gtfs_files do
        [%{} = file_1, file_2] when file_1 == %{} -> [gtfs_file, file_2]
        [%{"url" => ""}, file_2] -> [gtfs_file, file_2]
        [file_1, _file_2] -> [file_1, gtfs_file]
      end

    socket =
      socket
      |> assign(:gtfs_files, gtfs_files)
      |> push_event("store", %{key: "cle", data: Jason.encode!(gtfs_files)})

    {:noreply, socket}
  end

  def handle_info(
        {:notification, :gossip, %{"complete" => job_id, "gtfs_diff_id" => gtfs_diff_id}},
        socket
      ) do
    if socket.assigns.job_id == job_id do
      {:noreply, socket |> assign(:job_executing, false) |> assign(:gtfs_diff_id, gtfs_diff_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_url", %{"index" => index}, socket) do
    gtfs_files = socket.assigns.gtfs_files

    updated_gtfs_files =
      case index do
        "0" -> [nil, gtfs_files |> Enum.at(1)]
        "1" -> [gtfs_files |> Enum.at(0), nil]
      end

    socket = socket |> assign(:gtfs_files, updated_gtfs_files) |> assign(:gtfs_diff_id, nil)

    {:noreply, socket}
  end

  def handle_event("manual_input", %{"_target" => [target]} = params, socket) do
    gtfs_files =
      case target do
        "url1" -> socket.assigns.gtfs_files |> List.replace_at(0, %{"type" => "manual", "url" => params["url1"]})
        "url2" -> socket.assigns.gtfs_files |> List.replace_at(1, %{"type" => "manual", "url" => params["url2"]})
      end

    socket =
      socket
      |> assign(:gtfs_files, gtfs_files)
      |> push_event("store", %{key: "cle", data: Jason.encode!(gtfs_files)})

    {:noreply, socket}
  end

  def handle_event("compare", _, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    [gtfs_file_name_2, gtfs_file_name_1] =
      socket.assigns.gtfs_files
      |> Enum.map(fn %{"url" => url} ->
        {:ok, %{status_code: 200, body: body}} = http_client.get(url, [], follow_redirect: true)
        file_name = Ecto.UUID.generate()
        filepath = file_name |> tmp_filepath()
        filepath |> File.write!(body)
        upload_to_s3(filepath, file_name)
        file_name
      end)

    %{id: job_id} =
      %{
        gtfs_file_name_1: gtfs_file_name_1,
        gtfs_file_name_2: gtfs_file_name_2,
        bucket: Transport.S3.bucket_name(:gtfs_diff)
      }
      |> Transport.Jobs.GtfsDiff.new()
      |> Oban.insert!()

    {:noreply, socket |> assign(:job_executing, true) |> assign(:job_id, job_id)}
  end

  def handle_event("localStorageUpdate", %{"gtfs_files" => gtfs_files}, socket)
      when not is_nil(gtfs_files) do
    gtfs_files = gtfs_files |> Jason.decode!()

    socket = socket |> assign(:gtfs_files, gtfs_files)

    {:noreply, socket}
  end

  def handle_event("localStorageUpdate", _, socket) do
    {:noreply, socket}
  end

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:gtfs_diff, File.read!(file_path), path)
  end

  def tmp_filepath(filename), do: Path.join(System.tmp_dir!(), filename)

  def show([nil, nil]), do: "hidden"
  def show(_), do: nil
end
