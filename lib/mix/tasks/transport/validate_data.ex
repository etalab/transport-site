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
      %{project: project, name: dataset.slug, url: dataset.download_url}
      |> DataValidation.create_feed_source
      |> case do
        {:ok, feed_source} ->
          :ok = DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
          Logger.info(" <message>  Validating dataset")
          Logger.info(" <slug>     #{dataset.slug}")
        {:error, error} ->
          Logger.error("<message>  Unable to create feed source: #{inspect(error)}")
          Logger.error("<slug>     #{dataset.slug}")
      end
    end)
  end
end
