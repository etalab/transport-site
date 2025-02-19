defmodule TransportWeb.Live.GTFSDiffSelectLive do
  @moduledoc """
  Beta functionality: generate GTFS file diffs online
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext
  alias TransportWeb.GTFSDiffExplain

  import TransportWeb.Live.GTFSDiffSelectLive.Analysis
  import TransportWeb.Live.GTFSDiffSelectLive.Results
  import TransportWeb.Live.GTFSDiffSelectLive.Setup
  import TransportWeb.Live.GTFSDiffSelectLive.Shared
  import TransportWeb.Live.GTFSDiffSelectLive.Steps

  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> clean_slate()
     |> allow_upload(:gtfs,
       accept: ~w(.zip),
       max_entries: 2,
       max_file_size: max_file_size_mb() * 1_000_000,
       auto_upload: true
     )}
  end

  def handle_event("validate", _params, socket) do
    socket =
      socket
      |> assign(:error_msg, nil)
      |> assign(:diff_logs, [])
      |> assign(:results, %{})

    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :gtfs, ref)}
  end

  def handle_event("switch-uploads", _, socket) do
    {:noreply, update(socket, :uploads, &switch_uploads/1)}
  end

  def handle_event("clear-uploads", _, socket) do
    socket =
      Enum.reduce(socket.assigns[:uploads].gtfs.entries, socket, fn entry, socket ->
        cancel_upload(socket, :gtfs, entry.ref)
      end)

    {:noreply, socket}
  end

  def handle_event("start-over", _, socket) do
    {:noreply, clean_slate(socket)}
  end

  def handle_event("select-file", %{"file" => file}, socket) do
    {:noreply, update(socket, :results, set(:selected_file, file))}
  end

  def handle_event("gtfs_diff", _, socket) do
    send(self(), :enqueue_job)

    socket =
      socket
      |> assign(:current_step, :analysis)
      |> scroll_to_steps()

    {:noreply, socket}
  end

  def handle_info(:enqueue_job, socket) do
    [gtfs_file_name_2, gtfs_file_name_1] =
      consume_uploaded_entries(socket, :gtfs, fn %{path: path},
                                                 %Phoenix.LiveView.UploadEntry{client_name: original_file_name} ->
        file_name = Path.basename(path)
        stream_to_s3(path, file_name)
        {:ok, %{uploaded_file_name: file_name, original_file_name: original_file_name}}
      end)

    :ok = Oban.Notifier.listen([:gossip])

    %{id: job_id} =
      %{
        gtfs_file_name_1: gtfs_file_name_1.uploaded_file_name,
        gtfs_file_name_2: gtfs_file_name_2.uploaded_file_name,
        gtfs_original_file_name_1: gtfs_file_name_1.original_file_name,
        gtfs_original_file_name_2: gtfs_file_name_2.original_file_name,
        bucket: Transport.S3.bucket_name(:gtfs_diff),
        locale: Gettext.get_locale()
      }
      |> Transport.Jobs.GTFSDiff.new()
      |> Oban.insert!()

    socket =
      socket
      |> assign(:job_id, job_id)
      |> assign(:diff_logs, [dgettext("gtfs-diff", "Job started")])

    {:noreply, socket}
  end

  def handle_info({:generate_diff_summary, diff_file_url}, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    socket =
      case http_client.get(diff_file_url) do
        {:error, error} ->
          socket
          |> assign(:error_msg, HTTPoison.Error.message(error))

        {:ok, %{status_code: 200, body: body}} ->
          diff = Transport.GTFSDiff.parse_diff_output(body)

          diff_summary = diff |> GTFSDiffExplain.diff_summary()
          diff_explanations = diff |> GTFSDiffExplain.diff_explanations() |> drop_empty()

          files_with_changes =
            diff_summary
            |> Map.values()
            |> Enum.concat()
            |> Enum.map(fn {{file, _, _}, _} -> file end)
            |> Enum.sort()
            |> Enum.dedup()

          selected_file =
            case files_with_changes do
              [] -> nil
              _ -> Kernel.hd(files_with_changes)
            end

          update_many(socket, :results, [
            set(:diff_summary, diff_summary),
            set(:diff_explanations, diff_explanations),
            set(:files_with_changes, files_with_changes),
            set(:selected_file, selected_file)
          ])
      end

    {:noreply, socket}
  end

  # job has started
  def handle_info(
        {:notification, :gossip, %{"started" => job_id}},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    Process.send_after(self(), :timeout, Transport.Jobs.GTFSDiff.job_timeout_sec() * 1_000)
    {:noreply, socket}
  end

  # notifications about the ongoing job
  def handle_info(
        {:notification, :gossip, %{"running" => job_id, "log" => log}},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    {:noreply, socket |> update(:diff_logs, fn logs -> Enum.concat(logs, [log]) end)}
  end

  # job is complete
  def handle_info(
        {:notification, :gossip,
         %{
           "complete" => job_id,
           "diff_file_url" => diff_file_url,
           "gtfs_original_file_name_1" => gtfs_original_file_name_1,
           "gtfs_original_file_name_2" => gtfs_original_file_name_2
         }},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    send(self(), {:generate_diff_summary, diff_file_url})
    Oban.Notifier.unlisten([:gossip])

    updates = [
      set(:diff_file_url, diff_file_url),
      set(:gtfs_original_file_name_1, gtfs_original_file_name_1),
      set(:gtfs_original_file_name_2, gtfs_original_file_name_2)
    ]

    {:noreply,
     socket
     |> assign(:current_step, :results)
     |> update_many(:results, updates)
     |> scroll_to_steps()}
  end

  # job took too long
  def handle_info(:timeout, socket) do
    socket =
      if is_nil(socket.assigns[:diff_file_url]) do
        # no diff_file_url: job has not finished
        Oban.Notifier.unlisten([:gossip])

        assign(socket, :error_msg, timeout_msg())
      else
        socket
      end

    {:noreply, socket}
  end

  # catch-all
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @doc """
  iex> Gettext.put_locale("en")
  iex> timeout_msg()
  "Job aborted, the diff is taking too long (> 30 min)."
  iex> Gettext.put_locale("fr")
  iex> timeout_msg()
  "Traitement annulé, cela prend trop de temps (plus de 30 minutes)."
  """
  def timeout_msg do
    minutes = round(Transport.Jobs.GTFSDiff.job_timeout_sec() / 60)

    dgettext("validations", "Job aborted, the diff is taking too long (> %{minutes} min).", minutes: minutes)
  end

  defp scroll_to_steps(socket) do
    push_event(socket, "gtfs-diff:scroll-to-steps", %{})
  end

  defp update_many(socket, key, fns) do
    update(socket, key, sequence(fns))
  end

  defp sequence(fns) do
    fn hash0 -> Enum.reduce(fns, hash0, fn f, hash -> f.(hash) end) end
  end

  defp set(key, value) do
    fn hash -> Map.put(hash, key, value) end
  end

  defp stream_to_s3(file_path, path) do
    Transport.S3.stream_to_s3!(:gtfs_diff, file_path, path, acl: :public_read)
  end

  defp switch_uploads(uploads) do
    Map.update!(uploads, :gtfs, fn gtfs ->
      Map.update!(gtfs, :entries, &Enum.reverse/1)
    end)
  end

  defp drop_empty([]), do: nil
  defp drop_empty(otherwise), do: otherwise

  defp clean_slate(socket) do
    socket
    |> assign(:current_step, :setup)
    |> assign(:diff_logs, [])
    |> assign(:error_msg, nil)
    |> assign(:results, %{})
  end
end
