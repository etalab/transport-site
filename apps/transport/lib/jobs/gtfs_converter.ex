defmodule Transport.Jobs.GtfsConverter do
  @moduledoc """
  Provides some functions to convert GTFS to another format
  """
  alias DB.{DataConversion, Repo, ResourceHistory}
  import Ecto.Query

  @spec enqueue_all_conversion_jobs(binary(), module()) :: :ok
  def enqueue_all_conversion_jobs(format, conversionJob) when format in ["GeoJSON", "NeTEx"] do
    query =
      ResourceHistory
      |> where(
        [_r],
        fragment(
          """
          payload ->>'format'='GTFS'
          AND
          payload ->>'uuid' NOT IN
          (SELECT resource_history_uuid::text FROM data_conversion WHERE convert_from='GTFS' and convert_to=?)
          """,
          ^format
        )
      )
      |> select([r], r.id)

    stream = Repo.stream(query)

    Repo.transaction(fn ->
      stream
      |> Stream.each(fn id ->
        %{"resource_history_id" => id}
        |> conversionJob.new()
        |> Oban.insert()
      end)
      |> Stream.run()
    end)

    :ok
  end

  def is_resource_gtfs?(%{payload: %{"format" => "GTFS"}}), do: true

  def is_resource_gtfs?(_), do: false

  @spec format_exists?(binary(), any()) :: boolean
  def format_exists?(format, %{payload: %{"uuid" => resource_uuid}}) do
    DataConversion
    |> Repo.get_by(convert_from: "GTFS", convert_to: format, resource_history_uuid: resource_uuid) !== nil
  end

  def format_exists?(_, _), do: false
end
