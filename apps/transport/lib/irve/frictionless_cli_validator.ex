defmodule Transport.IRVE.FrictionlessCLIValidator do
  @moduledoc """
  While potentially usable outside the IRVE scope, this code is currently
  only used by IRVE, and no attempt is made to make it more generic than needed.
  """

  @latest_static_irve_schema "https://schema.data.gouv.fr/schemas/etalab/schema-irve-static/latest/schema-static.json"

  @doc """
  File location can be a file path or a url.

  Schema as well, which allows local caching of the schema to avoid numerous HTTP requests when
  validating a lot of files.
  """
  def validate(file_location, schema \\ @latest_static_irve_schema) do
    cmd = "frictionless"
    args = ["validate", file_location, "--schema", schema, "--json", "--format", "csv"]

    {output, result} = System.cmd(cmd, args)

    output = Jason.decode!(output)

    case result do
      0 ->
        {:ok, output}

      1 ->
        {:error, output}
    end
  end
end
