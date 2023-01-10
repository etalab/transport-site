defmodule TransportWeb.GTFSDiffLive do
  # use Phoenix.Component
  use Phoenix.LiveView, container: {:div, class: "gtfs-diff-selector"}
  alias Phoenix.PubSub
  alias TransportWeb.Router.Helpers, as: Routes

  def render(assigns) do
    ~H"""
    <div id="gtfs-diff-widget" class={show(@urls)} phx-hook="GTFSDiff">
      <strong>Comparer 2 GTFS</strong>
      <form phx-change="manual_input">
        <%= for i <- 0..1 do %>
          <% url = Enum.at(@urls, i) || "" %>
          <div class="gtfs-diff-url pt-6">
            <input type="text" value={url} name={"url#{i+1}"} id={"url#{i+1}"} placeholder="url" />
            <%= if url != "" do %>
              <i class="icon icon--trash" phx-click="delete_url" phx-value-index={i} aria-hidden="true"></i>
            <% end %>
          </div>
        <% end %>
      </form>
      <%= if is_nil(@gtfs_diff_id) and not Enum.any?(@urls, &is_nil/1) do %>
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

  def mount(_params, %{}, socket) do
    if connected?(socket) do
      PubSub.subscribe(TransportWeb.PubSub, "diff")
      :ok = Oban.Notifier.listen([:gossip])
    end

    socket =
      socket
      |> assign(:urls, [nil, nil])
      |> assign(:job_executing, false)
      |> assign(:gtfs_diff_id, nil)

    {:ok, socket}
  end

  def handle_info({"add_url", url}, socket) do
    urls =
      case socket.assigns.urls do
        [nil, url2] -> [url, url2]
        [url1, _url2] -> [url1, url]
      end

    socket =
      socket
      |> assign(:urls, urls)
      |> push_event("store", %{key: "cle", data: urls})

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
    urls = socket.assigns.urls

    updated_urls =
      case index do
        "0" -> [nil, urls |> Enum.at(1)]
        "1" -> [urls |> Enum.at(0), nil]
      end

    socket = socket |> assign(:urls, updated_urls) |> assign(:gtfs_diff_id, nil)

    {:noreply, socket}
  end

  def handle_event("manual_input", params, socket) do
    urls = [params["url1"], params["url2"]]

    socket =
      socket
      |> assign(:urls, urls)
      |> push_event("store", %{key: "cle", data: urls})

    {:noreply, socket}
  end

  def handle_event("compare", _, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    [gtfs_file_name_2, gtfs_file_name_1] =
      socket.assigns.urls
      |> Enum.map(fn url ->
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

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:gtfs_diff, File.read!(file_path), path)
  end

  def tmp_filepath(filename), do: Path.join(System.tmp_dir!(), filename)

  def show([nil, nil]), do: "hidden"
  def show(_), do: nil
end
