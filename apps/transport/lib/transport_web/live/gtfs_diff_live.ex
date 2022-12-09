defmodule TransportWeb.GTFSDiffLive do
  # use Phoenix.Component
  use Phoenix.LiveView, container: {:div, class: "gtfs-diff-selector"}
  alias Phoenix.PubSub

  def render(assigns) do
    ~H"""
    <div class={show(@urls)}>
      <strong>Comparer 2 GTFS</strong>
      <%= for i <- 0..1 do %>
      <% url = Enum.at(@urls, i) || "" %>
      <div class="gtfs-diff-url pt-6">
      <input
        type="text"
        value={url}
        name="url1"
        id="url1"
        placeholder={"url#{i+1}"}
      />
      <%= if url != "" do %>
        <i class="icon icon--trash" phx-click="delete_url" phx-value-index={i} aria-hidden="true"></i>
      <% end %>
      </div>
      <% end %>
      <button class="button" phx-click="compare">Comparer</button>
      <%= if @job_executing do %>
        <i class="icon icon--spinner" aria-hidden="true"></i>
      <% end %>
      <%= if @diff_file_url do %>
        <%= @diff_file_url %>
      <% end %>
    </div>
    """
  end

  def mount(_params, %{}, socket) do
    if connected?(socket) do
      PubSub.subscribe(TransportWeb.PubSub, "diff")
      :ok = Oban.Notifier.listen([:gossip])
    end

    socket = socket |> assign(:urls, [nil, nil]) |> assign(:job_executing, false) |> assign(:diff_file_url, nil)

    {:ok, socket}
  end

  def handle_info({"add_url", url}, socket) do
    urls =
      case socket.assigns.urls do
        [nil, url2] -> [url, url2]
        [url1, _url2] -> [url1, url]
      end

    {:noreply, assign(socket, :urls, urls)}
  end

  def handle_info({:notification, :gossip, %{"complete" => job_id, "diff_file_url" => diff_file_url}}, socket) do
    if socket.assigns.job_id == job_id do
      {:noreply, socket |> assign(:job_executing, false) |> assign(:diff_file_url, diff_file_url)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_url", %{"index" => index}, socket) do
    urls = socket.assigns.urls

    updated_urls =
      case index do
        "0" -> [nil, urls |> Enum.at(1)]
        "1" -> [urls |> Enum.at(0), nil]
      end

    {:noreply, assign(socket, :urls, updated_urls)}
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
