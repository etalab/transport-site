defmodule Transport.Jobs.GtfsConverter do
@moduledoc """
Provides some functions to convert GTFS to another format
"""
alias DB.{Repo, ResourceHistory}
import Ecto.Query

@spec enqueue_all_conversion_jobs(binary(), module()) :: :ok
def enqueue_all_conversion_jobs(format, conversionJob) do
  query =
    ResourceHistory
    |> where(
      [_r],
      fragment("""
      payload ->>'format'='GTFS'
      AND
      payload ->>'uuid' NOT IN
      (SELECT resource_history_uuid::text FROM data_conversion WHERE convert_from='GTFS' and convert_to='?')
      """, ^format)
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
end
