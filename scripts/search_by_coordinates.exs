defmodule TestSearchByCoordinates do
  import Ecto.Query

  def aom_select() do
    DB.AOM
    |> select([a], map(a,[:id, :nom, :insee_commune_principale, :departement, :forme_juridique, :siren]))
  end

  def city_select() do
    DB.Commune
    |> select([c], map(c,[:id, :nom, :insee, :siren, :departement_insee, :region_id]))
  end

  def department_select() do
    DB.Departement
    |> select([d], map(d,[:id, :nom, :insee, :zone]))
  end

  def region_select() do
    DB.Region
    |> select([r], map(r,[:id, :nom, :insee]))
  end

  def dataset_select() do
    DB.Dataset
    |> select([d], map(d,[:id, :custom_title, :organization]))
  end

  def where_coordinates(query, lon, lat) do
    query |> where([c], fragment("st_contains(geom, st_setsrid(st_point(?, ?), 4326))", ^lon, ^lat))
  end

  def aom_by_coordinates(lon, lat) do
    aom_select() |> where_coordinates(lon, lat)
  end

  def city_by_coordinates(lon, lat) do
     city_select() |> where_coordinates(lon, lat)
  end

  def department_by_coordinates(lon, lat) do
    department_select() |> where_coordinates(lon, lat)
  end

  def region_by_coordinates(lon, lat) do
    department_select() |> where_coordinates(lon, lat)
  end

  def territory_list_by_coordinates(lon, lat) do
    city = city_by_coordinates(lon, lat) |> DB.Repo.one()
    aom = aom_by_coordinates(lon, lat) |> DB.Repo.one() # Note : aom shouldn’t overlap
    department = department_select() |> where([d], d.insee == ^city.departement_insee) |> DB.Repo.one()
    region = region_select() |> where([r], r.id == ^city.region_id) |> DB.Repo.one()

    # Fetch datasets that cover the point:
    #  Datasets where the region is the covered area
    region_as_covered_area_datasets = dataset_select() |> where([d], d.region_id == ^region.id) |> DB.Repo.all()
    #  Datasets where the aom is the coveed_area
    aom_as_covered_area_datasets = dataset_select() |> where([d], d.aom_id == ^aom.id) |> DB.Repo.all()
    # Datasets that have a city list that includes the city
    city_as_covered_area_datasets = DB.Dataset |> Ecto.assoc(:communes) |> where([dataset: d, communes: c], c.id == ^city.id) |> DB.Repo.all()
    # Fetch datasets that have the AOM as legal owner
    # Fetch datasets that have the region as legal owner


    %{
      city: city,
      aom: aom,
      department: department,
      region: region,
      city_as_covered_area_datasets: city_as_covered_area_datasets,
      region_as_covered_area_datasets: region_as_covered_area_datasets,
      aom_as_covered_area_datasets: aom_as_covered_area_datasets
    }
  end
end

TestSearchByCoordinates.territory_list_by_coordinates(2.373912, 48.844578) |> IO.inspect()
