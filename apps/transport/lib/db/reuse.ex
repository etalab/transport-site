defmodule DB.Reuse do
  @moduledoc """
  Represents data.gouv.fr reuses.
  """
  use TypedEctoSchema
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  typed_schema "reuse" do
    field(:datagouv_id, :string)
    field(:title, :string)
    field(:slug, :string)
    field(:url, :string)
    field(:type, :string)
    field(:description, :string)
    field(:remote_url, :string)
    field(:organization, :string)
    field(:organization_id, :string)
    field(:owner, :string)
    field(:owner_id, :string)
    field(:image, :string)
    field(:featured, :boolean)
    field(:archived, :boolean)
    field(:topic, :string)
    field(:tags, {:array, :string})
    field(:metric_discussions, :integer)
    field(:metric_datasets, :integer)
    field(:metric_followers, :integer)
    field(:metric_views, :integer)
    field(:created_at, :utc_datetime_usec)
    field(:last_modified, :utc_datetime_usec)

    many_to_many(:datasets, DB.Dataset, join_through: "reuse_dataset", on_replace: :delete)
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [
      :title,
      :slug,
      :url,
      :type,
      :description,
      :remote_url,
      :organization,
      :organization_id,
      :owner,
      :owner_id,
      :image,
      :featured,
      :topic,
      :created_at,
      :last_modified
    ])
    |> transform_datagouv_id(attrs)
    |> transform_metric_keys(attrs)
    |> transform_archived(attrs)
    |> transform_tags(attrs)
    |> validate_required([
      :datagouv_id,
      :title,
      :slug,
      :url,
      :type,
      :description,
      :remote_url,
      :featured,
      :archived,
      :topic,
      :tags,
      :metric_discussions,
      :metric_datasets,
      :metric_followers,
      :metric_views,
      :created_at,
      :last_modified
    ])
    |> cast_datasets(attrs)
  end

  defp cast_datasets(%Ecto.Changeset{} = changeset, %{"datasets" => datasets}) do
    datagouv_ids = (datasets || "") |> String.split(",")

    datasets =
      DB.Dataset.base_query()
      |> where([dataset: d], d.datagouv_id in ^datagouv_ids)
      |> select([dataset: d], [:id])
      |> DB.Repo.all()

    changeset |> put_assoc(:datasets, datasets)
  end

  defp transform_archived(%Ecto.Changeset{} = changeset, %{"archived" => archived}) do
    put_change(changeset, :archived, String.downcase(archived) == "true")
  end

  defp transform_tags(%Ecto.Changeset{} = changeset, %{"tags" => tags}) do
    put_change(changeset, :tags, String.split(tags || "", ","))
  end

  defp transform_datagouv_id(%Ecto.Changeset{} = changeset, %{"id" => id}) do
    changeset |> put_change(:datagouv_id, id) |> delete_change(:id)
  end

  defp transform_metric_keys(%Ecto.Changeset{} = changeset, attributes) do
    attributes
    |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "metric.") end)
    |> Enum.map(fn {k, v} -> {k |> String.replace(".", "_") |> String.to_existing_atom(), v} end)
    |> Enum.reduce(changeset, fn {k, v}, changeset -> put_change(changeset, k, v) end)
  end
end
