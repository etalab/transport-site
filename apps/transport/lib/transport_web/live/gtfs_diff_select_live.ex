defmodule TransportWeb.Live.GtfsDiffSelectLive do
  @moduledoc """
  Beta functionality: generate GTFS file diffs online
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers

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
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :gtfs, ref)}
  end

  def handle_event("gtfs_diff", _, socket) do
    [gtfs_file_name_1, gtfs_file_name_2] =
      consume_uploaded_entries(socket, :gtfs, fn %{path: path}, _entry ->
        file_name = Path.basename(path)
        upload_to_s3(path, file_name)
        {:ok, file_name}
      end)

    :ok = Oban.Notifier.listen([:gossip])

    %{id: job_id} =
      Transport.Jobs.GtfsDiff.new(%{
        gtfs_file_name_1: gtfs_file_name_1,
        gtfs_file_name_2: gtfs_file_name_2,
        bucket: Transport.S3.bucket_name(:gtfs_diff)
      })
      |> Oban.insert!()

    socket =
      receive do
        {:notification, :gossip, %{"complete" => ^job_id, "diff_file_url" => diff_file_url}} ->
          IO.puts("Other job complete!")
          socket |> assign(:diff_file_url, diff_file_url)
      after
        30_000 ->
          IO.puts("Other job didn't finish in 30 seconds!")
          socket
      end

    {:noreply, socket}
  end

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:gtfs_diff, File.read!(file_path), path)
  end

  def diff_summary(diff) do
    order = %{"file" => 0, "column" => 1, "row" => 2}

    diff
    |> Enum.frequencies_by(fn r ->
      {Map.get(r, :file), Map.get(r, :action), Map.get(r, :target)}
    end)
    |> Enum.sort_by(fn {{_, _, target}, _} -> order |> Map.fetch!(target) end)
    |> Enum.map(fn {{file, action, target}, n} ->
      "file #{file}, #{action} #{n} #{target}"
    end)
  end

  def uploads_are_valid(%{gtfs: %{entries: gtfs}}) do
    gtfs |> Enum.count() == 2 and gtfs |> Enum.all?(& &1.valid?)
  end

  defp error_to_string(:too_large), do: "File is too large, must be <2MB"
  defp error_to_string(:too_many_files), do: "You must select 2 files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
end
