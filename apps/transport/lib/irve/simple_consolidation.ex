defmodule Transport.IRVE.SimpleConsolidation do
  @moduledoc """
  A module that consolidates simple IRVE data for faster access.
  """

  def process do
    # Get list of datagouv resources
    resource_list()
    # Then for each resource, launch a kind of job that will dl the resource, etc.
    |> Enum.take(2)
    |> Task.async_stream(
      fn resource ->
        process_resource(resource)
      end,
      on_timeout: :kill_task,
      max_concurrency: 10
    )
    |> Stream.map(fn {:ok, result} -> result end)

    :ok
  end

  def resource_list do
    Transport.IRVE.Extractor.datagouv_resources()
    |> Transport.IRVE.RawStaticConsolidation.exclude_irrelevant_resources()
    # |> maybe_filter(options[:filter])
    |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
  end

  def process_resource(resource) do
    # if resource.resource_id == "7a5acb37-32c9-48bf-a14f-cac23bb9aff0" do
    #  :timer.sleep(10_000)
    # end
    # resource.resource_id
  end
end
