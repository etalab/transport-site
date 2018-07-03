defmodule Mix.Tasks.Transport.ValidateData do
  @moduledoc """
  Queues all ok data to validation
  """

  use Mix.Task
  alias Transport.ReusableData.Dataset
  alias Transport.DataValidation
  require Logger

  @pool DBConnection.Poolboy

  def run(_) do
    Mix.Task.run("app.start", [])

    {:ok, project} = DataValidation.create_project(%{name: "Transport"})

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
  end
end
