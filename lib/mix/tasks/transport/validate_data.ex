defmodule Mix.Tasks.Transport.ValidateData do
  @moduledoc """
  Queues all ok data for validation.
  """

  use Mix.Task
  alias Transport.DataValidation
  alias Transport.ReusableData
  require Logger

  @concurrency 5
  @timeout 60_000

  def run(_) do
    Mix.Task.run("app.start", [])

    Task.Supervisor.start_link()
    |> ok!
    |> Task.Supervisor.async_stream_nolink(
      ReusableData.list_datasets(),
      &validate/1,
      max_concurrency: @concurrency,
      timeout: @timeout
    )
    |> Enum.to_list()
  end

  defp validate(dataset) do
    with {:ok, dataset} <- DataValidation.find_dataset(dataset),
         {:ok, _} <- DataValidation.validate_dataset(dataset) do
      Logger.info(dataset.download_url)
    else
      {:error, error} ->
        Logger.error(dataset.download_url)
        Logger.error(error)
    end
  end

  defp ok!({:ok, result}), do: result
end
