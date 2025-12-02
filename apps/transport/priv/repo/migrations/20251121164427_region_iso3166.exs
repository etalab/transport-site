defmodule DB.Repo.Migrations.RegionIso3166 do
  use Ecto.Migration

  def change do
    alter table(:region) do
      add(:iso3166, :string)
    end

    execute("""
    UPDATE region SET iso3166 = t.iso3166
    FROM (
      select 'FR-ARA' iso3166, 'Auvergne-Rhône-Alpes' nom
      union
      select 'FR-BFC' iso3166, 'Bourgogne-Franche-Comté' nom
      union
      select 'FR-BRE' iso3166, 'Bretagne' nom
      union
      select 'FR-CVL' iso3166, 'Centre-Val de Loire' nom
      union
      select 'FR-GES' iso3166, 'Grand Est' nom
      union
      select 'FR-HDF' iso3166, 'Hauts-de-France' nom
      union
      select 'FR-NOR' iso3166, 'Normandie' nom
      union
      select 'FR-NAQ' iso3166, 'Nouvelle-Aquitaine' nom
      union
      select 'FR-OCC' iso3166, 'Occitanie' nom
      union
      select 'FR-PDL' iso3166, 'Pays de la Loire' nom
      union
      select 'FR-PAC' iso3166, 'Provence-Alpes-Côte d’Azur' nom
      union
      select 'FR-IDF' iso3166, 'Île-de-France' nom
      union
      select 'FR-974' iso3166, 'La Réunion' nom
      union
      select 'FR-971' iso3166, 'Guadeloupe' nom
      union
      select 'FR-973' iso3166, 'Guyane' nom
      union
      select 'FR-976' iso3166, 'Mayotte' nom
      union
      select 'FR-972' iso3166, 'Martinique' nom
      union
      select 'FR-NC' iso3166, 'Nouvelle-Calédonie' nom
      union
      select 'FR-20R' iso3166, 'Corse' nom
    ) t
    WHERE t.nom = region.nom
    """)
  end
end
