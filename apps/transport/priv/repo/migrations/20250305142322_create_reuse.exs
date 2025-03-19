defmodule DB.Repo.Migrations.CreateReuse do
  use Ecto.Migration

  def change do
    create table(:reuse) do
      add(:datagouv_id, :string)
      add(:title, :string)
      add(:slug, :string)
      add(:url, :string, size: 500)
      add(:type, :string)
      add(:description, :text)
      add(:remote_url, :string, size: 1_000)
      add(:organization, :string)
      add(:organization_id, :string)
      add(:owner, :string)
      add(:owner_id, :string)
      add(:image, :string)
      add(:featured, :boolean, default: false)
      add(:archived, :boolean, default: false)
      add(:topic, :string)
      add(:tags, {:array, :string})
      add(:metric_discussions, :integer)
      add(:metric_datasets, :integer)
      add(:metric_followers, :integer)
      add(:metric_views, :integer)
      add(:created_at, :utc_datetime_usec)
      add(:last_modified, :utc_datetime_usec)
    end
  end
end
