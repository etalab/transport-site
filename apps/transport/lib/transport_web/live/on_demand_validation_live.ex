defmodule TransportWeb.Live.OnDemandValidationLive do
  @moduledoc """
  This Live view is in charge of displaying an on demand validation:
  waiting, error and results screens.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext
  import Shared.DateTimeDisplay, only: [format_datetime_to_paris: 3]
  import Shared.Validation.TableSchemaValidator, only: [validata_web_url: 1]
  import Ecto.Query

  def mount(
        _params,
        %{"locale" => locale, "validation_id" => validation_id, "current_url" => current_url} = _session,
        socket
      ) do
    Gettext.put_locale(locale)
    data = %{validation_id: validation_id, current_url: current_url, locale: locale}
    {:ok, socket |> assign(data) |> update_data()}
  end

  defp update_data(socket) do
    validation = DB.MultiValidation |> preload(:metadata) |> DB.Repo.get!(socket_value(socket, :validation_id))

    socket =
      assign(socket,
        last_updated_at: DateTime.utc_now(),
        validation: validation,
        gtfs_rt_feed: maybe_gtfs_rt_feed(socket, validation)
      )

    unless is_final_state?(socket) do
      schedule_next_update_data()
    end

    if gtfs_validation_completed?(socket) do
      redirect(socket, to: socket_value(socket, :current_url))
    else
      socket
    end
  end

  def handle_info(:update_data, socket) do
    {:noreply, update_data(socket)}
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1_000)
  end

  defp is_final_state?(socket) do
    case socket_value(socket, :validation) do
      %DB.MultiValidation{oban_args: oban_args} -> oban_args["state"] in ["error", "completed"]
      _ -> false
    end
  end

  defp gtfs_validation_completed?(socket) do
    case socket_value(socket, :validation) do
      %DB.MultiValidation{oban_args: oban_args} ->
        oban_args["type"] == "gtfs" and oban_args["state"] == "completed"

      _ ->
        false
    end
  end

  defp socket_value(%Phoenix.LiveView.Socket{assigns: assigns}, key), do: Map.fetch!(assigns, key)

  def format_datetime(dt, locale) do
    format_datetime_to_paris(dt, locale, with_seconds: true)
  end

  defp maybe_gtfs_rt_feed(
         socket,
         %DB.MultiValidation{oban_args: %{"type" => "gtfs-rt", "state" => "completed"}} = validation
       ) do
    lang = socket_value(socket, :locale)
    url = Map.fetch!(validation.oban_args, "gtfs_rt_url")

    Transport.Cache.API.fetch(
      "gtfs_rt_feed_validation_#{validation.id}_#{lang}",
      fn ->
        case Transport.GTFSRT.decode_remote_feed(url) do
          {:ok, feed} ->
            %{
              alerts: Transport.GTFSRT.service_alerts_for_display(feed, lang),
              feed_is_too_old: Transport.GTFSRT.feed_is_too_old?(feed),
              feed_timestamp_delay: Transport.GTFSRT.feed_timestamp_delay(feed),
              feed: feed
            }

          {:error, _} ->
            :error
        end
      end,
      :timer.minutes(1)
    )
  end

  defp maybe_gtfs_rt_feed(_, _), do: nil
end
