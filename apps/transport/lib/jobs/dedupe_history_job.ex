defmodule Transport.Jobs.DedupeHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `DedupeHistoryJob`.

  The goal is to remove resources that have been historicized
  multiple times in a row without changes.
  """
  use Oban.Worker, tags: ["history"]
  require Logger
  import Ecto.Query
  alias DB.{Repo, ResourceHistory}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ids = ResourceHistory |> distinct(true) |> select([r], r.datagouv_id) |> Repo.all()

    Logger.info("Dispatching #{Enum.count(ids)} DedupeHistoryJob jobs")

    ids
    |> Enum.map(fn datagouv_id ->
      %{datagouv_id: datagouv_id} |> Transport.Jobs.DedupeHistoryJob.new()
    end)
    |> Oban.insert_all()

    :ok
  end
end

defmodule Transport.Jobs.DedupeHistoryJob do
  @moduledoc """
  Job removing duplicates for a specific datagouv_id.
  """
  use Oban.Worker, unique: [period: 60 * 60, fields: [:args, :worker]], tags: ["history"], max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{Repo, ResourceHistory}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"datagouv_id" => datagouv_id}}) do
    objects = ResourceHistory |> where([r], r.datagouv_id == ^datagouv_id) |> order_by(:inserted_at) |> Repo.all()

    if Enum.count(objects) > 1 do
      to_delete =
        1..(Enum.count(objects) - 1)
        |> Enum.filter(&is_same?(Enum.at(objects, &1), Enum.at(objects, &1 - 1)))
        |> Enum.map(&Enum.at(objects, &1))

      remove_s3_objects(to_delete |> Enum.map(&Map.fetch!(&1.payload, "filename")))
      remove_resource_history_rows(to_delete |> Enum.map(& &1.id))
    end

    :ok
  end

  def is_same?(%ResourceHistory{} = r1, %ResourceHistory{} = r2) do
    MapSet.equal?(shas(r1), shas(r2))
  end

  defp remove_resource_history_rows(ids) do
    ResourceHistory |> where([r], r.id in ^ids) |> Repo.delete_all()
  end

  defp remove_s3_objects(paths) do
    paths |> Enum.each(&Transport.S3.delete_object(:history, &1))
  end

  defp shas(%ResourceHistory{payload: payload}) do
    MapSet.new(payload["zip_metadata"] |> Enum.map(& &1["sha256"]))
  end
end
