defmodule DB.Repo.Migrations.AddTitleResourceHistory do
  use Ecto.Migration

  def up do
    # Add the key `title` to the JSON payload and set it
    # to the resource's current title
    execute """
    update resource_history
    set payload = jsonb_set(payload, '{title}', to_jsonb(t.title))
    from (
      select datagouv_id, title
      from resource
    ) t
    where not (resource_history.payload ? 'title')
      and not (resource_history.payload ? 'from_old_system')
      and t.datagouv_id = resource_history.datagouv_id
    """
  end

  def down do
    # Removes the key `title` from the JSON payload
    execute "update resource_history set payload = payload - 'title'"
  end
end
