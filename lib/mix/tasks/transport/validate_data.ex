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
      %{project: project, name: dataset.slug, url: dataset.download_uri}
      |> DataValidation.create_feed_source
      |> case do
        {:ok, feed_source} ->
          :ok = DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
        {:error, error} -> Logger.error("Unable to create source feed: #{inspect(error)}")
      end
    end)
  end
end
