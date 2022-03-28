defmodule Transport.Jobs.Backfill.ResourceHistoryMetadataNonGTFS do
  @moduledoc """
  Backfill of ResourceHistory payload to fix metadata for
  non-GTFS resources with metadata specific to GTFS.

  See also `ResourceMetadataNonGTFS`.

  See https://github.com/etalab/transport-site/issues/2258
  """
  use Oban.Worker
  import Ecto.Query
  alias DB.{Repo, ResourceHistory}

  @backfill_delay 1

  @impl true
  def perform(%{args: %{"resource_history_id" => resource_history_id, "backfill" => true}}) do
    with :ok <- perform(%{args: %{"resource_history_id" => resource_history_id}}) do
      case fetch_next(resource_history_id) do
        next_id when is_integer(next_id) ->
          %{resource_history_id: next_id, backfill: true} |> new(schedule_in: @backfill_delay) |> Oban.insert()

        nil ->
          :ok
      end
    end
  end

  def perform(%{args: %{"resource_history_id" => resource_history_id}}) do
    update_resource_history(resource_history_id)
    :ok
  end

  def fetch_next(resource_history_id) do
    ResourceHistory
    |> where([rh], rh.id > ^resource_history_id)
    |> where([rh], fragment("payload ->>'format' != 'GTFS' and payload->'resource_metadata' \\? 'modes'"))
    |> order_by(asc: :id)
    |> limit(1)
    |> select([rh], rh.id)
    |> Repo.one()
  end

  def update_resource_history(resource_history_id) do
    ResourceHistory |> Repo.get!(resource_history_id) |> do_update()
  end

  def do_update(%ResourceHistory{payload: %{"format" => format, "resource_metadata" => %{"modes" => _}} = payload} = rh)
      when format != "GTFS" do
    rh
    |> Ecto.Changeset.change(%{payload: payload |> Map.put("resource_metadata", nil)})
    |> Repo.update!()
  end

  def do_update(%ResourceHistory{} = rh), do: rh
end
