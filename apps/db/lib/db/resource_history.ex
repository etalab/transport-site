defmodule DB.ResourceHistory do
  @moduledoc """
  ResourceHistory stores metadata when resources are historicized.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  @derive {Jason.Encoder, only: [:datagouv_id, :payload, :last_up_to_date_at, :inserted_at, :updated_at]}
  typed_schema "resource_history" do
    field(:datagouv_id, :string)
    field(:payload, :map)
    # the last moment we checked and the resource history was corresponding to the real online resource
    field(:last_up_to_date_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def latest_resource_history(resource_id) do
    DB.Resource
    |> join(:left, [r], rh in DB.ResourceHistory, on: r.datagouv_id == rh.datagouv_id)
    |> where([r, rh], r.id == ^resource_id)
    |> order_by([_r, rh], desc: rh.inserted_at)
    |> limit(1)
    |> select([_r, rh], rh.payload)
    |> DB.Repo.one()
  end

  def latest_resource_history_infos(resource_id) do
    resource_id
    |> latest_resource_history()
    |> case do
      %{"permanent_url" => url, "total_uncompressed_size" => size} -> %{url: url, size: size}
      _ -> nil
    end
  end
end
