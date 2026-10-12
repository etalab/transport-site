defmodule TransportWeb.Backoffice.CacheLive do
  @moduledoc """
  A view to help debug the Cachex memory cache.
  """
  use TransportWeb, :live_view
  import Transport.Application, only: [cache_name: 0]
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.Router.Helpers

  @impl true
  def mount(params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket = socket |> assign_filter(Map.get(params, "filter_key_name"))

       update_data(socket)
     end)}
  end

  defp assign_filter(socket, filter_key_name) do
    assign(socket,
      filter_key_name: filter_key_name,
      form: to_form(%{"filter_key_name" => filter_key_name}, as: :search_key_name)
    )
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      stats: compute_stats(socket)
    )
  end

  @impl true
  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  @impl true
  def handle_params(%{"filter_key_name" => filter_key_name}, _uri, socket) do
    socket = socket |> assign_filter(filter_key_name)

    {:noreply, update_data(socket)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, update_data(socket)}
  end

  @impl true
  def handle_event("delete_key", %{"key_name" => key_name}, socket) do
    Cachex.del(cache_name(), key_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"search_key_name" => %{"filter_key_name" => filter_key_name}}, socket) do
    socket =
      socket
      |> push_patch(to: backoffice_live_path(socket, __MODULE__, filter_key_name: filter_key_name))

    {:noreply, socket}
  end

  defp compute_stats(socket) do
    # See https://hexdocs.pm/cachex/Cachex.html#inspect/3
    nb_expired_keys = cache_name() |> Cachex.inspect({:expired, :count}) |> elem(1)
    nb_records = cache_name() |> Cachex.size() |> elem(1)
    keys = cache_keys(Map.get(socket.assigns, :filter_key_name))

    %{
      nb_expired_keys: nb_expired_keys,
      expired_keys: cache_name() |> Cachex.inspect({:expired, :keys}) |> elem(1) |> Enum.sort(),
      nb_records: nb_records,
      cache_size_binary: cache_name() |> Cachex.inspect({:memory, :binary}) |> elem(1),
      last_janitor_execution: last_janitor_execution(),
      keys: keys,
      nb_hidden_keys: nb_records - nb_expired_keys - Enum.count(keys)
    }
  end

  def format_ttl(nil) do
    "Pas de TTL"
  end

  def format_ttl(value) when is_integer(value) do
    Shared.DateTimeDisplay.relative_datetime_in_seconds(round(value / 1_000), "fr")
  end

  defp cache_keys(filter_key_name) do
    cache_name()
    |> Cachex.keys()
    |> elem(1)
    |> Enum.filter(fn key ->
      case filter_key_name do
        nil -> true
        value -> String.contains?(key, value)
      end
    end)
    |> Enum.sort()
    |> Enum.map(fn key ->
      %{name: key, ttl: cache_name() |> Cachex.ttl(key) |> elem(1)}
    end)
  end

  defp last_janitor_execution do
    cache_name()
    |> Cachex.inspect({:janitor, :last})
    |> elem(1)
    |> case do
      %{started: started} -> DateTime.from_unix!(started, :millisecond)
      _ -> "pas encore exécuté"
    end
  end
end
