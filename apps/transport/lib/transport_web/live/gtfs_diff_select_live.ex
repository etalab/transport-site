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

  def mount(params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    socket = clean_slate(socket)

    case params do
      :not_mounted_at_router -> {:ok, setup_uploads(socket)}
      %{} -> {:ok, setup_uploads(socket)}
      _ -> {:ok, do_handle_params(socket, params)}
    end
  end

  def handle_params(params, _uri, socket) do
    {:noreply, do_handle_params(socket, params)}
  end

  defp do_handle_params(socket, params) do
    socket |> set_profile(params) |> handle_urls(params)
  end

  defp handle_urls(socket, %{"reference_url" => reference_url, "modified_url" => modified_url}) do
    skip_uploads_and_diff_urls(socket, reference_url, modified_url)
  end

  defp handle_urls(socket, _) do
    setup_uploads(socket)
  end

  defp skip_uploads_and_diff_urls(socket, reference_url, modified_url) do
    socket
    |> assign(current_step: :analysis)
    |> trigger_job(reference_url, modified_url, socket.assigns[:profile])
    |> scroll_to_steps()
  end

  def set_profile(socket, %{"profile" => profile}) do
    assign(socket, profile: profile)
  end

  def set_profile(socket, _) do
    assign(socket, profile: "core")
  end

  def handle_event("validate", _params, socket) do
    {:noreply, assign(socket, error_msg: nil)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :gtfs, ref)}
  end

  def handle_event("switch-uploads", _, socket) do
    {:noreply, switch_uploads(socket)}
  end

  def handle_event("clear-uploads", _, socket) do
    {:noreply, clear_uploads(socket)}
  end

  def handle_event("start-over", _, socket) do
    {:noreply, clean_slate(socket)}
  end

  def handle_event("select-file", %{"file" => file}, socket) do
    {:noreply, set_selected_file(socket, file)}
  end

  def handle_event("gtfs_diff", _, socket) do
    send(self(), :enqueue_job)

    socket =
      socket
      |> assign(current_step: :analysis)
      |> scroll_to_steps()

    {:noreply, socket}
  end

  def handle_info(:enqueue_job, socket) do
    [gtfs_file_2, gtfs_file_1] = read_uploaded_files(socket)

    {:noreply, socket |> trigger_job(gtfs_file_1, gtfs_file_2, socket.assigns[:profile])}
  end

  def handle_info({:generate_diff_summary, diff_file_url}, socket) do
    {:noreply, socket |> handle_diff_summary(diff_file_url)}
  end

  def handle_info(
        {:notification, :gossip, notification},
        %{assigns: %{job_id: job_id}} = socket
      ) do
    {:noreply, handle_job_notification(notification, job_id, socket)}
  end

  # job took too long
  def handle_info(:timeout, socket) do
    socket =
      if is_nil(socket.assigns[:diff_file_url]) do
        on_timeout(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  # catch-all
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp trigger_job(socket, gtfs_file_1, gtfs_file_2, profile) do
    :ok = listen_job_notifications()

    job_id = schedule_job(gtfs_file_1, gtfs_file_2, profile)

    socket
    |> assign(job_id: job_id)
    |> assign(diff_logs: [dgettext("gtfs-diff", "Job started")])
  end

  # job has started
  def handle_job_notification(%{"started" => job_id}, job_id, socket) do
    schedule_timeout()
    socket
  end

  # notifications about the ongoing job
  def handle_job_notification(%{"running" => job_id, "log" => log}, job_id, socket) do
    append_log(socket, log)
  end

  # job is complete
  def handle_job_notification(
        %{
          "complete" => job_id,
          "diff_file_url" => diff_file_url,
          "context" => context
        },
        job_id,
        socket
      ) do
    generate_diff_summary(diff_file_url)
    unlisten_job_notifications()

    socket
    |> present_results(diff_file_url, context)
    |> scroll_to_steps()
  end

  def handle_job_notification(_, _, socket), do: socket

  defp read_uploaded_files(socket) do
    consume_uploaded_entries(socket, :gtfs, &consume_uploaded_entry/2)
  end

  defp consume_uploaded_entry(%{path: path}, %Phoenix.LiveView.UploadEntry{client_name: original_file_name}) do
    file_name = Path.basename(path)
    stream_to_s3(path, file_name)
    {:ok, %{uploaded_file_name: file_name, original_file_name: original_file_name}}
  end

  defp schedule_job(gtfs_url_1, gtfs_url_2, profile) when is_binary(gtfs_url_1) do
    schedule_job(
      %{
        gtfs_url_1: gtfs_url_1,
        gtfs_url_2: gtfs_url_2,
        gtfs_original_file_name_1: "reference.zip",
        gtfs_original_file_name_2: "modified.zip"
      },
      profile
    )
  end

  defp schedule_job(
         %{uploaded_file_name: gtfs_object_1, original_file_name: gtfs_original_file_name_1},
         %{
           uploaded_file_name: gtfs_object_2,
           original_file_name: gtfs_original_file_name_2
         },
         profile
       ) do
    schedule_job(
      %{
        gtfs_object_1: gtfs_object_1,
        gtfs_object_2: gtfs_object_2,
        gtfs_original_file_name_1: gtfs_original_file_name_1,
        gtfs_original_file_name_2: gtfs_original_file_name_2
      },
      profile
    )
  end

  defp schedule_job(args, profile) do
    %{id: job_id} =
      args
      |> Map.merge(%{
        locale: Gettext.get_locale(),
        profile: profile
      })
      |> Transport.Jobs.GTFSDiff.new()
      |> Oban.insert!()

    job_id
  end

  defp listen_job_notifications, do: Oban.Notifier.listen([:gossip])

  defp unlisten_job_notifications, do: Oban.Notifier.unlisten([:gossip])

  defp clean_slate(socket) do
    socket
    |> assign(current_step: :setup)
    |> assign(diff_logs: [])
    |> assign(error_msg: nil)
    |> assign(results: %{})
    |> assign(profile: "core")
  end

  defp setup_uploads(socket) do
    allow_upload(socket, :gtfs,
      accept: ~w(.zip),
      max_entries: 2,
      max_file_size: max_file_size_mb() * 1_000_000,
      auto_upload: true
    )
  end

  defp append_log(socket, log) do
    update(socket, :diff_logs, fn logs -> Enum.concat(logs, [log]) end)
  end

  defp generate_diff_summary(diff_file_url) do
    send(self(), {:generate_diff_summary, diff_file_url})
  end

  defp handle_diff_summary(socket, diff_file_url) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    case http_client.get(diff_file_url) do
      {:error, error} ->
        assign(socket, error_msg: HTTPoison.Error.message(error))

      {:ok, %{status_code: 200, body: body}} ->
        diff = Transport.GTFSDiff.parse_diff_output(body)

        update_results_with_diff(socket, diff)
    end
  end

  defp present_results(socket, diff_file_url, context) do
    updates = [
      set(:diff_file_url, diff_file_url),
      set(:context, context)
    ]

    socket
    |> assign(current_step: :results)
    |> update_many(:results, updates)
  end

  defp update_results_with_diff(socket, diff) do
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

  defp schedule_timeout do
    Process.send_after(self(), :timeout, Transport.Jobs.GTFSDiff.job_timeout_sec() * 1_000)
  end

  defp on_timeout(socket) do
    # no diff_file_url: job has not finished
    unlisten_job_notifications()

    assign(socket, error_msg: timeout_msg())
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

  defp set_selected_file(socket, file) do
    update(socket, :results, set(:selected_file, file))
  end

  defp switch_uploads(socket) do
    update(socket, :uploads, fn uploads ->
      Map.update!(uploads, :gtfs, fn gtfs ->
        Map.update!(gtfs, :entries, &Enum.reverse/1)
      end)
    end)
  end

  defp clear_uploads(socket) do
    {socket, _} = Phoenix.LiveView.Upload.maybe_cancel_uploads(socket)
    socket
  end

  defp drop_empty([]), do: nil
  defp drop_empty(otherwise), do: otherwise
end
