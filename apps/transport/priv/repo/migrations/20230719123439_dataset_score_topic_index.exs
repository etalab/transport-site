defmodule DB.Repo.Migrations.DatasetScoreTopicIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists(index(:dataset_score, [:topic]))
  end
end
