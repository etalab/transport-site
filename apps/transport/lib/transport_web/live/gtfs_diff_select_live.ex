defmodule TransportWeb.Live.GTFSDiffSelectLive do
  @moduledoc """
  Beta functionality: generate GTFS file diffs online
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext
  alias TransportWeb.GTFSDiffExplain

  @max_file_size_mb 10
  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> assign(:diff_logs, [])
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

  def handle_event("gtfs_diff", _, socket) do
    send(self(), :enqueue_job)
    {:noreply, socket |> assign(:job_running, true)}
  end

  def handle_info(:enqueue_job, socket) do
    [gtfs_file_name_2, gtfs_file_name_1] =
      consume_uploaded_entries(socket, :gtfs, fn %{path: path}, _entry ->
        file_name = Path.basename(path)
        upload_to_s3(path, file_name)
        {:ok, file_name}
      end)

    :ok = Oban.Notifier.listen([:gossip])

    %{id: job_id} =
      %{
        gtfs_file_name_1: gtfs_file_name_1,
        gtfs_file_name_2: gtfs_file_name_2,
        bucket: Transport.S3.bucket_name(:gtfs_diff)
      }
      |> Transport.Jobs.GTFSDiff.new()
      |> Oban.insert!()

    Process.send_after(self(), :timeout, Transport.Jobs.GTFSDiff.job_timeout())

    socket = socket |> assign(:job_id, job_id) |> assign(:diff_logs, ["job started"])
    {:noreply, socket}
  end

  def handle_info({:generate_diff_summary, diff_file_url}, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    %{status_code: 200, body: body} = http_client.get!(diff_file_url)
    diff = Transport.GTFSDiff.parse_diff_output(body)

    socket =
      socket
      |> assign(:diff_summary, diff |> GTFSDiffExplain.diff_summary())
      |> assign(:diff_explanations, diff |> GTFSDiffExplain.diff_explanations())

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
        {:notification, :gossip, %{"complete" => job_id, "diff_file_url" => diff_file_url}},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    send(self(), {:generate_diff_summary, diff_file_url})
    Oban.Notifier.unlisten([:gossip])
    {:noreply, socket |> assign(:diff_file_url, diff_file_url) |> assign(:diff_logs, []) |> assign(:job_running, false)}
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
          "Job aborted, the diff is taking too long (> #{Transport.Jobs.GTFSDiff.job_timeout()} sec)."
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

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:gtfs_diff, File.read!(file_path), path)
  end

  def uploads_are_valid(%{gtfs: %{entries: gtfs}}) do
    gtfs |> Enum.count() == 2 and gtfs |> Enum.all?(& &1.valid?)
  end

  defp error_to_string(:too_large), do: "File is too large, must be <#{@max_file_size_mb}MB"
  defp error_to_string(:too_many_files), do: "You must select 2 files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
end
