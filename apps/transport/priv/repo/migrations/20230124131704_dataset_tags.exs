defmodule DB.Repo.Migrations.DatasetTags do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:custom_tags, {:array, :string})
    end

    create(index("dataset", [:custom_tags], using: :gin))
  end
end
