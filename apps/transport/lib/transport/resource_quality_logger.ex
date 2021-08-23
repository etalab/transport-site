defmodule Transport.ResourceQualityLogger do
  @moduledoc """
  A module to launch the insertion in the DB of quality metrics about the resources
  """

  alias DB.{LogsResourceQuality, Repo, Resource}

  def insert_all_resources_logs do
    stream = Resource |> Repo.stream()

    Repo.transaction(fn ->
      stream
      |> Stream.map(fn resource ->
        %{
          resource_id: resource.id,
          is_available: resource.is_available,
          resource_end_date: resource.end_date,
          log_date: DateTime.utc_now()
        }
      end)
      |> Stream.chunk_every(500)
      |> Stream.each(fn changesets -> Repo.insert_all(LogsResourceQuality, changesets) end)
      |> Enum.to_list()
    end)
  end
end
