defmodule Transport.Jobs.Backfill.ResourceMetadataNonGTFS do
  @moduledoc """
  Backfill of Resource payload to fix metadata for
  non-GTFS resources with metadata specific to GTFS.

  See also `ResourceHistoryMetadataNonGTFS`.

  See https://github.com/etalab/transport-site/issues/2258
  """
  use Oban.Worker
  import Ecto.Query
  alias DB.{Repo, Resource}

  @backfill_delay 1

  @impl true
  def perform(%{args: %{"resource_id" => resource_id, "backfill" => true}}) do
    with :ok <- perform(%{args: %{"resource_id" => resource_id}}) do
      case fetch_next(resource_id) do
        next_id when is_integer(next_id) ->
          %{resource_id: next_id, backfill: true} |> new(schedule_in: @backfill_delay) |> Oban.insert()

        nil ->
          :ok
      end
    end
  end

  def perform(%{args: %{"resource_id" => resource_id}}) do
    update_resource(resource_id)
    :ok
  end

  def fetch_next(resource_id) do
    Resource
    |> where([r], r.id > ^resource_id)
    |> where([r], r.format != "GTFS" and fragment("metadata \\? 'modes'"))
    |> order_by(asc: :id)
    |> limit(1)
    |> select([r], r.id)
    |> Repo.one()
  end

  def update_resource(resource_id) do
    Resource |> Repo.get!(resource_id) |> do_update()
  end

  def do_update(%Resource{format: format, metadata: %{"modes" => _}} = resource) when format != "GTFS" do
    resource |> Ecto.Changeset.change(%{metadata: nil}) |> Repo.update!()
  end

  def do_update(%Resource{} = resource), do: resource
end
