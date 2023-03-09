defmodule DB.Repo.Migrations.AddMailingListTitleContact do
  use Ecto.Migration

  def change do
    alter table(:contact) do
      # `first_name` and `last_name` can now be `null`
      modify :first_name, :string, null: true, from: {:string, null: false}
      modify :last_name, :string, null: true, from: {:string, null: false}
      # add new `column` for contacts that are not "real humans", for example mailing lists
      add :mailing_list_title, :string, null: true
    end
  end
end
