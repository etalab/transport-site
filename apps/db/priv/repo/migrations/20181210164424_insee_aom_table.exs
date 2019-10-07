defmodule DB.Repo.Migrations.InseeAomTable do
  use Ecto.Migration
  def up do

    create table("commune") do
      add :insee, :string
      add :nom, :string
      add :wikipedia, :string
      add :surf_ha, :float
      add :geom, :geometry
    end

    flush()

    # HTTPoison.start
    # "https://www.data.gouv.fr/fr/datasets/r/4aa66fae-3dc4-4445-8c8c-e30b55ffb6a3"
    # |> HTTPoison.get([], hackney: [follow_redirect: true])
    # |> case do
    #   {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> body
    #   error -> raise(error)
    # end
    # |> String.split("\n")
    # |> Enum.filter(fn line -> line != "" end)
    # |> Enum.map(fn line -> String.replace(line, "'", "''") end)
    # |> Enum.map(fn line ->
    #   [insee, nom, wikipedia, surf_ha, geom] = String.split(line, "\t")
    #   execute("""
    #        INSERT INTO commune(insee, nom, wikipedia, surf_ha, geom)
    #        VALUES('#{insee}', '#{nom}', '#{wikipedia}', #{surf_ha}, '#{geom}')
    #   """)
    # end)

    create index("commune", [:insee])
  end

  def down do
    drop table("commune")
  end
end
