defmodule Transport.IRVE.V3.Validator do
  @moduledoc """
  Entry point of the IRVE v3 validator, side by side with the v2 one (`Transport.IRVE.Validator`), which it
  leaves untouched. Validates any of the 3 files of the v3 data model, each against its vendored schema.

  Data model (3 files, keys, diagram): https://github.com/etalab/schema-irve/blob/v3.0.0-alpha.1/docs/note-conception-irve-v3.md#2-modèle-de-données
  """

  alias Transport.IRVE.V3.{FieldChecks, Reader, Report}

  @schemas %{
    statique: "schema-irve-statique-v3.json",
    dynamique: "schema-irve-dynamique-v3.json",
    tarifs: "schema-irve-tarifs-v3.json"
  }

  @doc """
  Validates the given file contents, keyed by role (`:statique`, `:dynamique`, `:tarifs`), into a `Report`.
  """
  def validate(bodies) when is_map(bodies) do
    %Report{files: Map.new(bodies, fn {role, body} -> {role, validate_file(Map.fetch!(@schemas, role), body)} end)}
  end

  defp validate_file(schema_file, body) do
    schema = Transport.CachedFiles.read_json(schema_file)
    file = %{sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower), schema: schema["version"]}

    case Reader.read(body, Enum.map(schema["fields"], & &1["name"])) do
      {:ok, df} ->
        checks = df |> FieldChecks.run(FieldChecks.compile(schema)) |> Explorer.DataFrame.new()
        Map.merge(file, %{n_rows: Explorer.DataFrame.n_rows(df), file_errors: [], checks: checks})

      {:error, file_errors} ->
        Map.merge(file, %{n_rows: nil, file_errors: file_errors, checks: nil})
    end
  end
end
