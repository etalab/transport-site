defmodule DB.Reuse do
  @moduledoc """
  Represents data.gouv.fr reuses.
  """
  use TypedEctoSchema
  use Ecto.Schema
  use Gettext, backend: TransportWeb.Gettext
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

  def base_query, do: from(r in __MODULE__, as: :reuse)

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
      :topic,
      :created_at,
      :last_modified
    ])
    |> transform_datagouv_id(attrs)
    |> transform_metric_keys(attrs)
    |> transform_archived(attrs)
    |> transform_featured(attrs)
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

  def type_to_str(type) do
    %{
      "api" => dgettext("reuses", "api"),
      "application" => dgettext("reuses", "application"),
      "hardware" => dgettext("reuses", "hardware"),
      "idea" => dgettext("reuses", "idea"),
      "news_article" => dgettext("reuses", "news_article"),
      "paper" => dgettext("reuses", "paper"),
      "post" => dgettext("reuses", "post"),
      "visualization" => dgettext("reuses", "visualization")
    }
    |> Map.fetch!(type)
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

  defp transform_archived(%Ecto.Changeset{} = changeset, params) do
    transform_bool(changeset, :archived, params)
  end

  defp transform_featured(%Ecto.Changeset{} = changeset, params) do
    transform_bool(changeset, :featured, params)
  end

  def transform_bool(%Ecto.Changeset{} = changeset, key, params) do
    case Map.get(params, to_string(key)) do
      value when is_binary(value) -> put_change(changeset, key, String.downcase(value) == "true")
      value -> put_change(changeset, key, value)
    end
  end

  defp transform_tags(%Ecto.Changeset{} = changeset, %{"tags" => tags}) do
    put_change(changeset, :tags, String.split(tags || "", ",") |> Enum.reject(&(&1 == "")))
  end

  defp transform_datagouv_id(%Ecto.Changeset{} = changeset, %{"id" => id}) do
    changeset |> put_change(:datagouv_id, id) |> delete_change(:id)
  end

  defp transform_metric_keys(%Ecto.Changeset{} = changeset, attributes) do
    attributes
    |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "metric.") end)
    |> Enum.map(fn {k, v} ->
      {k |> String.replace(".", "_") |> String.to_existing_atom(), String.to_integer(v)}
    end)
    |> Enum.reduce(changeset, fn {k, v}, changeset -> put_change(changeset, k, v) end)
  end
end
