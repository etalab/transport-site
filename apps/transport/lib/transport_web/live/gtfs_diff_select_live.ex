defmodule TransportWeb.Live.GtfsDiffSelectLive do
  @moduledoc """
  Beta functionality: generate GTFS file diffs online
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> allow_upload(:gtfs,
       accept: ~w(.zip),
       max_entries: 2,
       max_file_size: 2_000_000,
       auto_upload: true
     )}
  end

  def handle_event("validate", _params, socket) do
    socket =
      socket
      |> assign(:diff_file_url, nil)
      |> assign(:error_msg, nil)
      |> assign(:diff_summary, nil)

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
    [gtfs_file_name_1, gtfs_file_name_2] =
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
      |> Transport.Jobs.GtfsDiff.new()
      |> Oban.insert!()

    socket =
      receive do
        {:notification, :gossip, %{"complete" => ^job_id, "diff_file_url" => diff_file_url}} ->
          send(self(), {:generate_diff_summary, diff_file_url})
          socket |> assign(:diff_file_url, diff_file_url)
      after
        120_000 ->
          socket |> assign(:error_msg, "Job aborted, the diff is taking too long (>120sec).")
      end

    {:noreply, socket |> assign(:job_running, false)}
  end

  def handle_info({:generate_diff_summary, diff_file_url}, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    %{status_code: 200, body: body} = http_client.get!(diff_file_url)
    diff = Transport.Beta.GTFS.parse_diff_output(body)
    diff_summary = diff |> diff_summary()

    {:noreply, socket |> assign(:diff_summary, diff_summary)}
  end

  def diff_summary(diff) do
    order = %{"file" => 0, "column" => 1, "row" => 2}

    diff
    |> Enum.frequencies_by(fn r ->
      {Map.get(r, "file"), Map.get(r, "action"), Map.get(r, "target")}
    end)
    |> Enum.sort_by(fn {{_, _, target}, _} -> order |> Map.fetch!(target) end)
    |> Enum.group_by(fn {{_file, action, _target}, _n} -> action end)
  end

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:gtfs_diff, File.read!(file_path), path)
  end

  def uploads_are_valid(%{gtfs: %{entries: gtfs}}) do
    gtfs |> Enum.count() == 2 and gtfs |> Enum.all?(& &1.valid?)
  end

  defp error_to_string(:too_large), do: "File is too large, must be <2MB"
  defp error_to_string(:too_many_files), do: "You must select 2 files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
end
