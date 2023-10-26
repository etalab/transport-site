defmodule DB.Repo.Migrations.GbfsMetricsRemove404Rows do
  use Ecto.Migration

  def up do
    # See https://github.com/etalab/transport-site/issues/3483
    execute("""
    delete from metrics
    where period >= '2023-09-15'::date and target in (
      'gbfs:city_name_lowercase', 'gbfs:foo',
      'gbfs:valence', 'gbfs:montpellier', 'gbfs:rouen', 'gbfs:marseille', 'gbfs:strasbourg'
    )
    """)
  end

  def down do
    IO.puts("no going back")
  end
end
