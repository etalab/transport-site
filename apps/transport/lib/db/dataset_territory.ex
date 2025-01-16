defmodule DB.DatasetTerritory do
  @moduledoc """
  Extension of dataset schema for code related to territories
  """
  import Ecto.Changeset
  import Ecto.Query

  def put_territories(changeset, params) do
    put_departements(changeset, params)
  end

  defp put_departements(changeset, %{"departements" => ""}), do: changeset

  defp put_departements(changeset, %{"departements" => departements}) do
    # This is not ideal, but at least it ensures that we don’t use a departement that doesn’t exist
    # I’m not sure if it’s possible to do this in a better way
    # Either only write the relationship table
    # Or pass a list of maps, but then we need the id of the departement, which means it wasn’t such a good idea
    # to rely on insee for the relationship
    departements =
      DB.Departement
      |> where([c], c.insee in ^departements)
      |> DB.Repo.all()

    # departements = departements |> Enum.map(fn insee -> %{insee: insee} end)

    put_assoc(changeset, :departements, departements)
  end

  defp put_departements(changeset, _), do: changeset
end
