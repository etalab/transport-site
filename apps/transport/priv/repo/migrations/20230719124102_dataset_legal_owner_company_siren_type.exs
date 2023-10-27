defmodule DB.Repo.Migrations.DatasetLegalOwnerCompanySirenType do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      modify(:legal_owner_company_siren, :string, size: 9, from: :integer)
    end
  end
end
