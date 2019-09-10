defmodule Transport.Repo.Migrations.ChangeSiren do
  use Ecto.Migration

  def change do
    alter table(:aom) do
      modify :siren, :string
    end
  end
end
