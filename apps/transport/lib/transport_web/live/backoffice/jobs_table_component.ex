defmodule JobsTableComponent do
  @moduledoc """
  A live view table for Oban jobs monitoring
  """
  use Phoenix.LiveComponent
  use Gettext, backend: TransportWeb.Gettext

  def render(%{state: _, locale: _, jobs: _} = assigns) do
    ~H"""
    <table class="table">
      <thead>
        <tr>
          <th>id</th>
          <th :if={is_nil(@state)}>{dgettext("backoffice", "state")}</th>
          <th>{dgettext("backoffice", "queue")}</th>
          <th>{dgettext("backoffice", "worker")}</th>
          <th>{dgettext("backoffice", "args")}</th>
          <th>{dgettext("backoffice", "inserted_at")}</th>
          <th :if={is_nil(@state) or @state in ["discarded", "retryable"]}>{dgettext("backoffice", "errors")}</th>
          <th :if={is_nil(@state) or @state in ["scheduled", "retryable"]}>{dgettext("backoffice", "scheduled_at")}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={job <- @jobs}>
          <td><.show_details supports_details={assigns[:supports_details] || false} job_id={job.id} /></td>
          <td :if={is_nil(@state)}><span class={"job-state job-state-#{job.state}"}>{job.state}</span></td>
          <td>{job.queue}</td>
          <td>{job.worker}</td>
          <td>{inspect(job.args)}</td>
          <td><.timestamp dt={job.inserted_at} locale={@locale} /></td>
          <td :if={is_nil(@state) or @state in ["discarded", "retryable"]}>
            <.compact_errors errors={job.errors} locale={@locale} />
          </td>
          <td :if={is_nil(@state) or @state in ["scheduled", "retryable"]}>
            <.timestamp dt={job.scheduled_at} locale={@locale} />
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  def render(%{jobs: _, locale: _} = assigns) do
    render(Map.merge(%{state: nil}, assigns))
  end

  defp show_details(%{supports_details: true, job_id: _} = assigns) do
    ~H"""
    <button class="show-details" phx-click="show-details" phx-value-job_id={@job_id}>{@job_id}</button>
    """
  end

  defp show_details(%{job_id: _} = assigns) do
    ~H"""
    {@job_id}
    """
  end

  defp timestamp(%{dt: _, locale: _} = assigns) do
    ~H"""
    <span class="timestamp" data-datetime={format_datetime(@dt, @locale)}>{format_time(@dt, @locale)}</span>
    """
  end

  defp format_time(dt, locale) do
    Shared.DateTimeDisplay.format_time_to_paris(dt, locale || "en", no_timezone: true, with_seconds: true)
  end

  defp format_datetime(dt, locale) do
    Shared.DateTimeDisplay.format_datetime_to_paris(dt, locale || "en", no_timezone: true, with_seconds: true)
  end

  defp compact_errors(%{errors: _, locale: _} = assigns) do
    ~H"""
    <ol class="errors">
      <li :for={error <- split_errors(@errors)}>
        <.timestamp dt={error.at} locale={@locale} /> : <code>{error.error}</code>
      </li>
    </ol>
    """
  end

  defp split_errors(errors), do: Enum.map(errors, &split_error/1)

  defp split_error(error) do
    %{
      at: Map.get(error, "at"),
      error: Map.get(error, "error", "") |> extract_message()
    }
  end

  defp extract_message(message) do
    message |> String.split("\n") |> List.first("") |> String.trim_leading("** ")
  end
end
