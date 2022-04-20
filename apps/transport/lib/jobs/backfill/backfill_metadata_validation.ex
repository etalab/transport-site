defmodule Transport.Jobs.Backfill.ResourceHistoryValidationMetadata do
  @moduledoc """
  Backfill of ResourceHistory payload to fix metadata for
  non-GTFS resources with metadata specific to GTFS.

  See also `ResourceMetadataNonGTFS`.

  See https://github.com/etalab/transport-site/issues/2258
  """
  use Oban.Worker
  import Ecto.Query
  alias DB.{Repo, Resource, ResourceHistory}

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
    |> join(:inner, [rh], r in Resource, on: r.datagouv_id == rh.datagouv_id)
    |> where([rh], rh.id > ^resource_history_id)
    |> where([rh], fragment("payload->'resource_metadata' \\? 'validation'"))
    |> order_by(asc: :id)
    |> limit(1)
    |> select([rh], rh.id)
    |> Repo.one()
  end

  def update_resource_history(resource_history_id) do
    ResourceHistory |> preload(:resource) |> Repo.get!(resource_history_id) |> do_update()
  end

  def do_update(
        %ResourceHistory{
          payload: %{"resource_metadata" => %{"validation" => _}} = payload,
          resource: %Resource{schema_name: schema_name} = resource
        } = rh
      )
      when not is_nil(schema_name) do
    hash = content_hash(rh)

    resource =
      resource
      |> struct(%{
        url: Map.fetch!(payload, "permanent_url"),
        metadata: Map.fetch!(payload, "resource_metadata"),
        content_hash: hash
      })

    {:ok, %{"metadata" => metadata}} = Resource.validate(resource)

    rh
    |> Ecto.Changeset.change(%{payload: Map.merge(payload, %{"resource_metadata" => metadata, "content_hash" => hash})})
    |> Repo.update!()
  end

  defp content_hash(%ResourceHistory{payload: %{"permanent_url" => url}}) do
    file_path = System.tmp_dir!() |> Path.join(Ecto.UUID.generate())

    try do
      %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url)
      File.write!(file_path, body)
      Hasher.get_file_hash(file_path)
    after
      File.rm(file_path)
    end
  end

  def http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
