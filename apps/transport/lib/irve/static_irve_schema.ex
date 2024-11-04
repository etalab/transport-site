defmodule Transport.IRVE.StaticIRVESchema do
  @moduledoc """
  A module providing programmatic access to the static IRVE schema,
  as stored in the source code.
  """

  @doc """
  Read & decode the content of the IRVE static schema.

  NOTE: this is not cached at the moment.
  """
  def schema_content do
    __ENV__.file
    |> Path.join("../../../../shared/meta/schema-irve-statique.json")
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end
end
