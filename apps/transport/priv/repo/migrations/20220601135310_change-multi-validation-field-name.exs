defmodule :"Elixir.DB.Repo.Migrations.Change_multi_validation_field_name" do
  use Ecto.Migration

  def change do
    rename table(:multi_validation), :transport_tools_version, to: :validator_version
  end
end
