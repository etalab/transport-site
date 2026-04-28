defmodule JobsTableComponent do
  @moduledoc """
  A live view table for Oban jobs monitoring
  """
  use Phoenix.LiveComponent
  use Gettext, backend: TransportWeb.Gettext

  def render(%{state: _, jobs: _} = assigns) do
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
          <td>{job.id}</td>
          <td :if={is_nil(@state)}><span class={"job-state job-state-#{job.state}"}>{job.state}</span></td>
          <td>{job.queue}</td>
          <td>{job.worker}</td>
          <td>{inspect(job.args)}</td>
          <td>{format_datetime(job.inserted_at)}</td>
          <td :if={is_nil(@state) or @state in ["discarded", "retryable"]}><.compact_errors errors={job.errors} /></td>
          <td :if={is_nil(@state) or @state in ["scheduled", "retryable"]}>{format_datetime(job.scheduled_at)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  def render(%{jobs: _} = assigns) do
    render(Map.merge(%{state: nil}, assigns))
  end

  defp format_datetime(dt) do
    Shared.DateTimeDisplay.format_datetime_to_paris(dt, "en", no_timezone: true, with_seconds: true)
  end

  defp compact_errors(%{errors: _} = assigns) do
    ~H"""
    <ol class="errors">
      <li :for={error <- split_errors(@errors)}>
        {error.at} : <code>{error.error}</code>
      </li>
    </ol>
    """
  end

  defp split_errors(errors), do: Enum.map(errors, &split_error/1)

  defp split_error(error) do
    %{
      at: Map.get(error, "at") |> maybe(&format_datetime/1),
      error: Map.get(error, "error", "") |> extract_message()
    }
  end

  defp maybe(nil, _f), do: nil
  defp maybe(value, f), do: f.(value)

  defp extract_message(message) do
    message |> String.split("\n") |> List.first("") |> String.trim_leading("** ")
  end
end
