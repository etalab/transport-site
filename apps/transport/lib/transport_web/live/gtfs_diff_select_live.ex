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
    [path_gtfs_1, path_gtfs_2] =
      consume_uploaded_entries(socket, :gtfs, fn %{path: path}, _entry ->
        file_name = Path.basename(path)
        dest = Path.join(System.tmp_dir!(), file_name)
        File.cp!(path, dest)
        {:ok, dest}
      end)

    unzip_1 = Transport.Beta.GTFS.unzip(path_gtfs_1)
    unzip_2 = Transport.Beta.GTFS.unzip(path_gtfs_2)

    diff = Transport.Beta.GTFS.diff(unzip_1, unzip_2)

    diff_summary =
      diff
      |> diff_summary()

    diff_output = diff |> Transport.Beta.GTFS.dump_diff() |> String.split("\r\n")

    socket =
      socket
      |> assign(:diff_summary, diff_summary)
      |> assign(:diff_output, diff_output)

    File.rm!(path_gtfs_1)
    File.rm!(path_gtfs_2)

    {:noreply, socket}
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
