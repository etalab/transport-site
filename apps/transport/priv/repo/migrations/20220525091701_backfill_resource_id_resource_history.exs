defmodule DB.Repo.Migrations.BackfillResourceIdResourceHistory do
  use Ecto.Migration

  def up do
    # Fill resource_id when datagouv_id exists and is not ambiguous.
    execute("""
      update resource_history set resource_id = t.id
      from (
        select datagouv_id, id
        from resource
        where datagouv_id in (
          select datagouv_id
          from resource
          group by 1
          having count(1) = 1
        )
      ) t where t.datagouv_id = resource_history.datagouv_id and resource_id is null;
    """)

    # Fill resource_id when URL matches, within the same dataset, only when resource_id is not already set.
    execute("""
      update resource_history set resource_id = t.id
      from (
        select dataset_id, url, id
        from resource
      ) t where t.url = resource_history.payload->'resource_metadata'->>'url' and t.dataset_id = (resource_history.payload->>'dataset_id')::bigint and resource_id is null;
    """)

    # Fill resource_id when title matches, within the same dataset, only when resource_id is not already set.
    execute("""
      update resource_history set resource_id = t.id
      from (
        select dataset_id, title, id
        from resource
      ) t where t.title = resource_history.payload->>'title' and t.dataset_id = (resource_history.payload->>'dataset_id')::bigint and resource_id is null;
    """)
  end

  def down do
    execute "UPDATE resource_history set resource_id = null;"
  end
end
