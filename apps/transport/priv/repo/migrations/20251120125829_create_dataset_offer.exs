defmodule DB.Repo.Migrations.CreateDatasetOffer do
  use Ecto.Migration

  def change do
    create table(:dataset_offer, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:offer_id, references(:offer, on_delete: :delete_all), null: false)
    end

    create(index("dataset_offer", [:dataset_id]))
    create(index("dataset_offer", [:offer_id]))
  end
end
