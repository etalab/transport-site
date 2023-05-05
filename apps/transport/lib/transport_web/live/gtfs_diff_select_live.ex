defmodule TransportWeb.Live.GTFSDiffSelectLive do
  @moduledoc """
  Beta functionality: generate GTFS file diffs online
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext

  @max_file_size_mb 4
  def mount(_params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)

    {:ok,
     socket
     |> assign(:uploaded_files, [])
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

    socket =
      receive do
        {:notification, :gossip, %{"complete" => ^job_id, "diff_file_url" => diff_file_url}} ->
          send(self(), {:generate_diff_summary, diff_file_url})
          socket |> assign(:diff_file_url, diff_file_url)
      after
        120_000 ->
          socket |> assign(:error_msg, "Job aborted, the diff is taking too long (>120sec).")
      end

    Oban.Notifier.unlisten([:gossip])
    {:noreply, socket |> assign(:job_running, false)}
  end

  def handle_info({:generate_diff_summary, diff_file_url}, socket) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    %{status_code: 200, body: body} = http_client.get!(diff_file_url)
    diff = Transport.GTFSDiff.parse_diff_output(body)

    socket =
      socket
      |> assign(:diff_summary, diff |> diff_summary())
      |> assign(:diff_explanations, diff |> diff_explanations())

    {:noreply, socket}
  end

  # catch-all
  def handle_info(_, socket) do
    {:noreply, socket}
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

  def explanation_add_file(explanations, %{"action" => "add", "file" => file, "target" => "file"}) do
    [~s(Un fichier nommé "#{file}" a été ajouté) | explanations]
  end

  def explanation_add_file(explanations, _), do: explanations

  def explanation_delete_file(explanations, %{"action" => "delete", "file" => file, "target" => "file"}) do
    [~s(Le fichier nommé "#{file}" a été supprimé) | explanations]
  end

  def explanation_delete_file(explanations, _), do: explanations

  def explanation_update_stop_name(
        explanations,
        %{
          "action" => "update",
          "file" => "stops.txt",
          "target" => "row",
          "identifier" => %{"stop_id" => stop_id},
          "new_value" => %{"stop_name" => new_stop_name},
          "initial_value" => %{"stop_name" => initial_stop_name}
        }
      ) do
    [
      ~s([stops.txt] Le nom du stop_id #{stop_id} a été modifié. Nom initial : "#{initial_stop_name}", nouvelle valeur : "#{new_stop_name}")
      | explanations
    ]
  end

  def explanation_update_stop_name(explanations, _) do
    explanations
  end

  def explanation_stop_wheelchair_access(
        explanations,
        %{
          "action" => "update",
          "file" => "stops.txt",
          "target" => "row",
          "identifier" => %{"stop_id" => stop_id},
          "new_value" => %{"wheelchair_boarding" => new_wheelchair_boarding},
          "initial_value" => %{"wheelchair_boarding" => initial_wheelchair_boarding}
        }
      )
      when new_wheelchair_boarding in ["1", "2"] do
    [
      ~s([stops.txt] Information sur l'accessibilité rajoutée au stop_id #{stop_id}, ancienne valeur : "#{initial_wheelchair_boarding}", nouvelle valeur : "#{new_wheelchair_boarding}")
      | explanations
    ]
  end

  def explanation_stop_wheelchair_access(explanations, _), do: explanations

  def diff_explanations(diffs) do
    diffs
    |> Enum.flat_map(fn diff ->
      diff =
        diff
        |> Map.update("initial_value", %{}, &try_jason_decode(&1))
        |> Map.update("new_value", %{}, &try_jason_decode(&1))
        |> Map.update("identifier", %{}, &try_jason_decode(&1))

      []
      |> explanation_add_file(diff)
      |> explanation_delete_file(diff)
      |> explanation_update_stop_name(diff)
      |> explanation_stop_wheelchair_access(diff)
    end)
  end

  def try_jason_decode(""), do: ""
  def try_jason_decode(input), do: Jason.decode!(input)

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
