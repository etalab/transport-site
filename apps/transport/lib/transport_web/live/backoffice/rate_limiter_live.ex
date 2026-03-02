defmodule TransportWeb.Backoffice.RateLimiterLive do
  use Phoenix.LiveView
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import Helpers, only: [format_number: 1]

  @impl true
  def mount(_params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket
       |> assign(%{
         phoenix_ddos_max_2min_requests: env_value_to_int("PHOENIX_DDOS_MAX_2MIN_REQUESTS"),
         phoenix_ddos_max_1hour_requests: env_value_to_int("PHOENIX_DDOS_MAX_1HOUR_REQUESTS"),
         phoenix_ddos_safelist_ips: env_value_to_list("PHOENIX_DDOS_SAFELIST_IPS"),
         phoenix_ddos_blocklist_ips: env_value_to_list("PHOENIX_DDOS_BLOCKLIST_IPS"),
         log_user_agent: env_value("LOG_USER_AGENT"),
         block_user_agent_keywords: env_value_to_list("BLOCK_USER_AGENT_KEYWORDS"),
         allow_user_agents: env_value_to_list("ALLOW_USER_AGENTS")
       })
       |> update_data()
     end)}
  end

  @impl true
  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      ips_in_jail: PhoenixDDoS.Jail.ips_in_jail()
    )
  end

  @impl true
  def handle_event("bail_ip_from_jail", %{"ip" => ip}, socket) do
    PhoenixDDoS.Jail.bail_out(ip)
    {:noreply, socket}
  end

  defp env_value(env_value), do: System.get_env(env_value)

  defp env_value_to_int(env_name) do
    env_name |> System.get_env("500") |> Integer.parse() |> elem(0)
  end

  defp env_value_to_list(env_name) do
    case System.get_env(env_name, "") do
      "" -> "<vide>"
      value -> value
    end
  end
end
