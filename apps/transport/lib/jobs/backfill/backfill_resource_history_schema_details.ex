defmodule Transport.Jobs.Backfill.ResourceHistorySchemaDetails do
  @moduledoc """
  Backfill of `schema_name` and `schema_version` for `DB.ResourceHistory` where
  it was not saved as this was introduced on 2022-05-11, see https://github.com/etalab/transport-site/pull/2386.
  """
  use Oban.Worker

  @impl true
  def perform(%{}) do
    execute("""
      update resource_history set payload = t.new_payload
      from (
        select
          r.id,
          r.schema_name,
          r.schema_version,
          rh.id resource_history_id,
          r.dataset_id,
          rh.payload,
          rh.payload || jsonb_set(jsonb_object_agg('schema_version', r.schema_version), '{schema_name}', to_jsonb(r.schema_name)) new_payload,
          rh.inserted_at
        from resource r
        join resource_history rh on rh.resource_id = r.id and not rh.payload ? 'schema_name'
        where not schema_name is null
        group by r.id, rh.id
      ) t where t.resource_history_id = resource_history.id;
    """)

    :ok
  end

  defp execute(query), do: query |> DB.Repo.query!()
end
