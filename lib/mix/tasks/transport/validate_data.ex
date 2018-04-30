defmodule Mix.Tasks.Transport.ValidateData do
  @moduledoc """
  Queues all ok data for validation.
  """

  use Mix.Task
  alias Transport.ReusableData
  alias Transport.DataValidation
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

<<<<<<< HEAD
    :mongo
    |> Mongo.find("datasets", %{}, pool: @pool)
    |> Enum.map(&Dataset.new/1)
    |> Enum.each(fn(dataset) ->
      %{project: project, name: dataset.id, url: dataset.download_uri}
      |> DataValidation.create_feed_source
      |> case do
        {:ok, feed_source} ->
          :ok = DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
          Logger.info(" <message>  Validating dataset")
          Logger.info(" <slug>     #{dataset.slug}")
          Logger.info(" <id>      #{dataset.id}")
        {:error, error} ->
          Logger.error("<message>  Unable to create feed source: #{inspect(error)}")
          Logger.info(" <slug>     #{dataset.slug}")
          Logger.error(" <id>     #{dataset.id}")
      end
    end)
=======
  defp validate(dataset) do
    with {:ok, dataset} <- DataValidation.find_dataset(dataset),
         {:ok, _} <- DataValidation.validate_dataset(dataset) do
      Logger.info(dataset.download_url)
    else
      {:error, error} ->
        Logger.error(dataset.download_url)
        Logger.error(error)
    end
>>>>>>> Validate datasets in parallel
  end

  defp ok!({:ok, result}), do: result
end
