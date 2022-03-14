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
      %{"permanent_url" => url, "file_size" => file_size} -> %{url: url, file_size: file_size}
      _ -> nil
    end
  end

  @spec latest_dataset_resources_history_infos(integer())::map()
  def latest_dataset_resources_history_infos(dataset_id) do
    DB.Resource
    |> join(:left, [r], d in DB.Dataset, on: r.dataset_id == d.id, as: :d)
    |> join(:left, [r], rh in DB.ResourceHistory, on: rh.datagouv_id == r.datagouv_id, as: :rh)
    |> where([r, d: d], d.id == ^dataset_id)
    |> order_by([rh: rh], desc: rh.inserted_at)
    |> distinct([r, rh: rh], rh.datagouv_id)
    |> select([r,rh: rh], {r.id, %{url: fragment("payload->>'permanent_url'"), file_size: fragment("payload->>'file_size'")}})
    |> DB.Repo.all()
    |> Enum.into(%{})
  end
end
