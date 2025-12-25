defmodule TransportWeb.Backoffice.IRVEDashboardLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import Helpers, only: [format_number_maybe_nil: 2]
  import Ecto.Query, only: [last: 2]

  @impl true
  def mount(_params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       :ok = Oban.Notifier.listen([:gossip])

       socket
       |> assign_data()
     end)}
  end

  @doc """
  A quick and dirty filter on some interesting fields, using downcase matching.
  """
  def must_list_resource?(resource, filtering_expression) do
    filtering_expression = filtering_expression |> String.downcase() |> String.trim()

    filtering_expression == "" ||
      String.contains?(resource["dataset_organisation_name"] |> String.downcase(), filtering_expression) ||
      String.contains?(
        format_validity(resource["valid"], resource["http_status"])
        |> inspect
        |> String.downcase(),
        filtering_expression
      )
  end

  def assign_data(socket) do
    socket
    |> assign(:running, false)
    |> assign(:latest_report, latest_report())
    |> assign(:filtering_expression, "")
  end

  @impl true
  def handle_event("change_form", params, socket) do
    socket =
      socket
      |> assign(:filtering_expression, params["config"]["filtering_expression"])

    {:noreply, socket}
  end

  @impl true
  def handle_event("analyze", _, socket) do
    # NOTE: the job is configured to be unique including executing state, so the rest
    # of the code here does not rely on the job id and assumes it is indeed unique
    Transport.Jobs.AnalyzeIRVEJob.new(%{})
    |> Oban.insert!()

    {:noreply, socket}
  end

  def update_assigns({"progress", progress}, socket) do
    socket
    |> assign(:running, true)
    |> assign(:completion_message, "#{progress}% complete…")
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
  def handle_info({:notification, :gossip, %{"type" => "analyze_irve"} = args}, socket) do
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

  # ignore other gossip
  @impl true
  def handle_info({:notification, :gossip, _args}, socket) do
    {:noreply, socket}
  end

  def latest_report do
    report =
      DB.ProcessingReport
      |> last(:id)
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
    |> Enum.sort_by(fn x -> x["line_count"] end, :desc)
  end

  def format_validity(false, 200), do: {:safe, "<strong class='red'>KO</strong>"}
  def format_validity(true, 200), do: "OK"
  def format_validity(nil, 200), do: "Non testé"
  # mostly there to handle 404/500. Ignore validity and assume the resource is not reachable at all
  def format_validity(_validity, http_status), do: {:safe, "<strong class='red'>KO (#{http_status})</strong>"}
end
