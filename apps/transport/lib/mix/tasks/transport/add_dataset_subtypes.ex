defmodule Mix.Tasks.Transport.AddDatasetSubtypes do
  @moduledoc """
  Create dataset subtypes.
  Run with `mix Transport.AddDatasetSubtypes`.
  """
  use Mix.Task
  require Logger

  def run(_params) do
    Mix.Task.run("app.start")

    insert!("public-transit", "urban")
    insert!("public-transit", "intercity")
    insert!("public-transit", "school")
    insert!("public-transit", "seasonal")
    insert!("public-transit", "zonal_drt")

    insert!("vehicles-sharing", "bicycle")
    insert!("vehicles-sharing", "scooter")
    insert!("vehicles-sharing", "carsharing")
    insert!("vehicles-sharing", "moped")
    insert!("vehicles-sharing", "freefloating")
  end

  def insert!(parent_type, slug) do
    DB.DatasetSubtype.changeset(%DB.DatasetSubtype{}, %{
      parent_type: parent_type,
      slug: slug
    })
    |> DB.Repo.insert!()
  end
end
