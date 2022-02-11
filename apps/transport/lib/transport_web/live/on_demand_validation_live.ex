defmodule TransportWeb.Live.OnDemandValidationLive do
  @moduledoc """
  This Live view is in charge of displaying an on demand validation:
  waiting, error and results screens.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import TransportWeb.Gettext

  def mount(params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)
    schedule_next_update_data()
    {:ok, socket |> assign(validation_id: params["id"]) |> update_data()}
  end

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      validation: DB.Repo.get(DB.Validation, socket.assigns()[:validation_id])
    )
  end

  def handle_info(:update_data, socket) do
    unless is_final_state?(socket) do
      schedule_next_update_data()
    end

    {:noreply, update_data(socket)}
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1_000)
  end

  defp is_final_state?(socket) do
    case socket.assigns()[:validation] do
      nil -> true
      %DB.Validation{on_the_fly_validation_metadata: metadata} -> metadata["state"] in ["error", "completed"]
      _ -> false
    end
  end
end
