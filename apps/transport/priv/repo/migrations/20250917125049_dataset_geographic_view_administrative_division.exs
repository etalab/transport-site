defmodule DB.Repo.Migrations.DatasetGeographicViewAdministrativeDivision do
  use Ecto.Migration

  def up do
    execute("DROP TRIGGER refresh_dataset_geographic_view_trigger ON dataset;")
    execute("DROP FUNCTION refresh_dataset_geographic_view;")
    execute("DROP MATERIALIZED VIEW dataset_geographic_view;")

    execute("""
    CREATE MATERIALIZED VIEW dataset_geographic_view AS
    select distinct
      d.id dataset_id,
      coalesce(c.region_id, r.id, c_epci.region_id, r_de.id) region_id,
      geo.geom
    from dataset d
    join dataset_declarative_spatial_area ddsa on ddsa.dataset_id = d.id
    join administrative_division ad on ad.id = ddsa.administrative_division_id
    left join commune c on c.insee = ad.insee and ad.type = 'commune'
    left join region r on r.insee = ad.insee and ad.type in ('region', 'pays')
    left join commune c_epci on c_epci.epci_insee = ad.insee and ad.type = 'epci'
    left join departement de on de.insee = ad.insee and ad.type = 'departement'
    left join region r_de on r_de.insee = de.region_insee
    join (
      select
        d.id dataset_id,
        st_union(geom) geom
      from dataset d
      join dataset_declarative_spatial_area ddsa on ddsa.dataset_id = d.id
      join administrative_division ad on ad.id = ddsa.administrative_division_id
      group by 1
    ) geo on geo.dataset_id = d.id
    WITH DATA;
    """)

    # Add an index on dataset_id since we'll often make a join on this
    execute("CREATE INDEX dataset_id_idx ON dataset_geographic_view (dataset_id);")

    # Define a trigger function to refresh the materialized view
    execute("""
      CREATE OR REPLACE FUNCTION refresh_dataset_geographic_view()
      RETURNS trigger AS $$
      BEGIN
        REFRESH MATERIALIZED VIEW dataset_geographic_view;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    """)

    # Call of the trigger
    execute("""
      CREATE TRIGGER refresh_dataset_geographic_view_trigger
      AFTER INSERT OR UPDATE OR DELETE
      ON dataset
      FOR EACH STATEMENT
      EXECUTE PROCEDURE refresh_dataset_geographic_view();
    """)
  end

  def down, do: IO.puts("No going back")
end
