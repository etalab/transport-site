defmodule DB.Repo.Migrations.AdministrativeDivisionPopulation do
  use Ecto.Migration

  def change do
    alter table(:administrative_division) do
      add(:population, :integer, null: true)
    end

    execute(
      """
      UPDATE administrative_division SET population = t.population
      FROM (
        SELECT insee, population
        FROM commune
      ) t
      WHERE t.insee = administrative_division.insee and type = 'commune';
      """,
      ""
    )

    execute(
      """
      UPDATE administrative_division SET population = t.population
      FROM (
        SELECT epci_insee insee, sum(population) population
        FROM commune
        WHERE epci_insee is not null
        group by 1
      ) t
      WHERE t.insee = administrative_division.insee and type = 'epci';
      """,
      ""
    )

    execute(
      """
      UPDATE administrative_division SET population = t.population
      FROM (
        SELECT departement_insee insee, sum(population) population
        FROM commune
        group by 1
      ) t
      WHERE t.insee = administrative_division.insee and type = 'departement';
      """,
      ""
    )

    execute(
      """
      UPDATE administrative_division SET population = t.population
      FROM (
        SELECT r.insee insee, sum(population) population
        FROM commune c
        join region r on r.id = c.region_id
        group by 1
      ) t
      WHERE t.insee = administrative_division.insee and type = 'region';
      """,
      ""
    )

    execute(
      """
      UPDATE administrative_division
      SET population = (select sum(population) from commune)
      where insee = 'FR';
      """,
      ""
    )

    execute(
      """
      ALTER TABLE administrative_division ALTER COLUMN population SET NOT NULL;
      """,
      ""
    )
  end
end
