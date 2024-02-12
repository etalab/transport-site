defmodule TransportWeb.Backoffice.IRVEDashboardLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.Router.Helpers

  @impl true
  def mount(_params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       :ok = Oban.Notifier.listen([:gossip])

       socket
       |> assign_data()
     end)}
  end

  def assign_data(socket) do
    socket
    |> assign(:running, false)
    |> assign(:latest_report, latest_report())
  end

  @impl true
  def handle_event("consolidate", _, socket) do
    # NOTE: the job is configured to be unique including executing state, so the rest
    # of the code here does not rely on the job id and assumes it is indeed unique
    Transport.Jobs.ConsolidateIRVEJob.new(%{})
    |> Oban.insert!()

    {:noreply, socket}
  end

  def update_assigns({"progress", progress}, socket) do
    socket
    |> assign(:running, true)
    |> assign(:completion_message, "#{progress}% complete...")
  end

  def update_assigns({"complete"}, socket) do
    socket
    |> assign(:running, false)
    |> assign(:completion_message, "completed!")
    |> assign(:latest_report, latest_report())
  end

  def update_assigns({"failed"}, socket) do
    socket
    |> assign(:running, false)
    |> assign(:completion_message, "failed!")
  end

  @impl true
  def handle_info({:notification, :gossip, %{"type" => "consolidation_irve"} = args}, socket) do
    socket =
      case args do
        %{"status" => "progress" = status, "progress" => progress} ->
          update_assigns({status, progress}, socket)

        %{"status" => "complete" = status} ->
          update_assigns({status}, socket)

        %{"status" => "failed" = status} ->
          update_assigns({status}, socket)
      end

    {:noreply, socket}
  end

  import Ecto.Query, only: [from: 2, first: 1]

  def latest_report do
    report =
      from(pr in DB.ProcessingReport, order_by: {:desc, :id}, limit: 1)
      |> first()
      |> DB.Repo.one()

    maybe_reformat_report(report)
  end

  def maybe_reformat_report(nil), do: nil

  def maybe_reformat_report(report) do
    %{
      inserted_at: report.inserted_at,
      resources: sort_resources(report.content["resources"])
    }
  end

  def sort_resources(resources) do
    resources
    |> Enum.sort_by(fn x -> [x["line_count"]] end, :desc)
  end

  def format_validity(false), do: {:safe, "<strong class='red'>KO</strong>"}
  def format_validity(true), do: "OK"
  def format_validity(nil), do: "Non testé"
end
