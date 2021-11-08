defmodule Transport.ObanLogger do
  @moduledoc """
    Logs the Oban job exceptions as warnings
  """
  require Logger

  def handle_event(
        [:oban, :job, :exception],
        %{duration: duration} = info,
        %{args: args, error: error, id: id, worker: worker},
        nil
      ) do
    Logger.warn(
      "Job #{id} handled by #{worker} called with args #{inspect(args)} failed in #{duration}. Error: #{inspect(error)}"
    )
  end

  def setup, do: :telemetry.attach("oban-logger", [:oban, :job, :exception], &handle_event/4, nil)
end
