defmodule Mix.Tasks.Transport.FetchValidationResults do
    @moduledoc """
    Fetches all namespaces of validated feeds
    """

    use Mix.Task
    alias Transport.ReusableData.Dataset
    alias Transport.DataValidation
    require Logger

    @pool DBConnection.Poolboy

    def run(_) do
      Mix.Task.run("app.start", [])

      # 1. Get the project
      {:ok, project} = DataValidation.find_project(%{name: "Transport"})

      # 2. Get all feed sources
      {:ok, feed_sources} = DataValidation.list_feed_sources(%{project: project})

      # 3. For each feed source, use the latest_version_id to get the namespace
      Enum.each(feed_sources, fn(feed_source) ->
        case feed_source.latest_version_id do
          nil -> Logger.warn("No latest version id for slug  #{feed_source.name}")
          latest_version_id ->
            {:ok, feed_version} = DataValidation.find_feed_version(
              %{
                project: project,
                latest_version_id: latest_version_id
              }
            )
            Mongo.find_one_and_update(
              :mongo,
              "datasets",
              %{"slug" => feed_source.name},
              %{"$set" => %{"catalogue_id" => feed_version.namespace}},
              pool: @pool
            )
        end
      end)
    end

  end
