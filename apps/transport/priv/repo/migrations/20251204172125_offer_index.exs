defmodule DB.Repo.Migrations.OfferIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists(unique_index(:offer, [:identifiant_offre]))
  end
end
