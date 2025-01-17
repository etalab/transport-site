defmodule DB.DatasetNewCoveredArea do
  @moduledoc """
  Extension of dataset schema for code related to covered area
  """
  import Ecto.Changeset
  import Ecto.Query

  def preload_covered_area_objects(dataset) do
    dataset
    |> DB.Repo.preload([:new_communes, :departements, :epcis, :regions])
  end

  def put_new_covered_area(changeset, params) do
    changeset
    |> put_administrative_division(:new_communes, params)
    |> put_administrative_division(:departements, params)
    |> put_administrative_division(:epcis, params)
    |> put_administrative_division(:regions, params)
  end

  defp put_administrative_division(changeset, level, params) do
    level_str = Atom.to_string(level)

    case params do
      %{^level_str => ""} ->
        changeset

      %{^level_str => insee_list} ->
        # This is not ideal, but at least it ensures that we don’t use a division that doesn’t exist
        # I’m not sure if it’s possible to do this in a better way
        # Either only write the relationship table
        # Or pass a list of maps, but then we need the id of the departement, which means it wasn’t such a good idea
        # to rely on insee for the relationship
        administrative_divisions_in_db =
          case level do
            :new_communes -> DB.Commune
            :departements -> DB.Departement
            :epcis -> DB.EPCI
            :regions -> DB.Region
          end
          |> where([a], a.insee in ^insee_list)
          |> DB.Repo.all()

        put_assoc(changeset, level, administrative_divisions_in_db)

      _ ->
        changeset
    end
  end
end
