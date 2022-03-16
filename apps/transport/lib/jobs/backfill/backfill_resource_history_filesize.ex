defmodule Transport.Jobs.Backfill.ResourceHistoryFileSize do
  @moduledoc """
  Backfill of ResourceHistory payload to fill filesize information for all rows.
  """
  use Oban.Worker
  import Ecto.Query

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
    update_resource_filesize(resource_history_id)
    :ok
  end

  def fetch_next(resource_history_id) do
    DB.ResourceHistory
    |> where([rh], rh.id > ^resource_history_id)
    |> order_by(asc: :id)
    |> limit(1)
    |> select([rh], rh.id)
    |> DB.Repo.one()
  end

  def update_resource_filesize(resource_history_id) do
    DB.ResourceHistory
    |> DB.Repo.get!(resource_history_id)
    |> do_update()
  end

  # update the zip resources history
  def do_update(%{payload: %{"total_compressed_size" => total_compressed_size} = payload} = rh) do
    payload = payload |> Map.put("filesize", total_compressed_size)

    rh
    |> Ecto.Changeset.change(%{payload: payload})
    |> DB.Repo.update!()
  end

  # update the others
  def do_update(%{payload: %{"permanent_url" => url} = payload} = rh) do
    # Clever Cloud provides the file size in the http response headers <3
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    {:ok, %{headers: headers}} = http_client.head(url)
    {_, filesize} = headers |> Enum.find(fn {h, _} -> h == "content-length" end)

    payload = payload |> Map.put("filesize", filesize |> String.to_integer())

    rh
    |> Ecto.Changeset.change(%{payload: payload})
    |> DB.Repo.update!()
  end
end
