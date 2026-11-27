defmodule Transport.IRVE.V3.ValidatorTest do
  use ExUnit.Case, async: true
  alias Explorer.{DataFrame, Series}

  alias Transport.IRVE.V3.{
    DynamicFixtureGenerator,
    Report,
    StaticFixtureGenerator,
    TarifsFixtureGenerator,
    Validator
  }

  @generators %{statique: StaticFixtureGenerator, dynamique: DynamicFixtureGenerator, tarifs: TarifsFixtureGenerator}

  # Valid rows for the 3 files, consistent with each other.
  defp valid_rows do
    statique = StaticFixtureGenerator.generate(seed: 7, stations: 20, networks: 3)

    %{
      statique: statique,
      dynamique: DynamicFixtureGenerator.generate(statique),
      tarifs: TarifsFixtureGenerator.generate(statique)
    }
  end

  defp to_csv(rows), do: Map.new(rows, fn {role, rows} -> {role, @generators[role].to_csv(rows)} end)

  defp validate_rows(rows), do: rows |> to_csv() |> Validator.validate()

  # Sets `field` to `value` on the first row of the `role` file.
  defp put_first(rows, role, field, value),
    do: update_in(rows[role], &List.update_at(&1, 0, fn row -> %{row | field => value} end))

  # `{row index, code}` of every failing check of a file.
  defp failures(report, role) do
    checks = report.files[role].checks
    for code <- DataFrame.names(checks), {false, row} <- Enum.with_index(Series.to_list(checks[code])), do: {row, code}
  end

  test "the generated files are valid, and described by their checksum" do
    bodies = to_csv(valid_rows())
    report = Validator.validate(bodies)

    assert Report.valid?(report)

    for {role, body} <- bodies do
      assert report.files[role].sha256 == :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      assert report.files[role].schema == "v3.0.0-alpha.1"
    end
  end

  for {role, field, value, code} <- [
        {:statique, "siren_amenageur", "12345678", "siren_amenageur:pattern"},
        {:statique, "contact_operateur", "nobody", "contact_operateur:format"},
        {:statique, "nb_pdc", 0, "nb_pdc:minimum"},
        {:statique, "puissance_nominale_kw", 1001, "puissance_nominale_kw:maximum"},
        {:statique, "horodatage_maj", "2024-12-17T13:13:31", "horodatage_maj:type"},
        {:statique, "prise_type_2", "VRAI", "prise_type_2:type"},
        {:statique, "equipement_afir", nil, "equipement_afir:required"},
        {:dynamique, "etat_pdc", "cassé", "etat_pdc:enum"},
        {:tarifs, "tarif_id", "T001", "tarif_id:pattern"},
        {:tarifs, "element_index", "1.5", "element_index:type"},
        {:tarifs, "min_price", -1, "min_price:minimum"},
        {:tarifs, "price_components", nil, "price_components:required"}
      ] do
    test "#{role} #{field} = #{inspect(value)} fails #{code} only" do
      rows = put_first(valid_rows(), unquote(role), unquote(field), unquote(value))
      assert failures(validate_rows(rows), unquote(role)) == [{0, unquote(code)}]
    end
  end

  test "a missing value fails required, and the other rules of the field are not evaluated" do
    checks = valid_rows() |> put_first(:statique, "nb_pdc", nil) |> validate_rows() |> then(& &1.files.statique.checks)

    assert {checks["nb_pdc:required"][0], checks["nb_pdc:type"][0], checks["nb_pdc:minimum"][0]} == {false, nil, nil}
  end

  test "a value of the wrong type fails its type only, its constraints are not evaluated" do
    report = valid_rows() |> put_first(:statique, "station_latitude", "north") |> validate_rows()
    checks = report.files.statique.checks

    assert failures(report, :statique) == [{0, "station_latitude:type"}]
    assert {checks["station_latitude:minimum"][0], checks["station_latitude:maximum"][0]} == {nil, nil}
  end

  describe "file-level errors" do
    defp file_errors(body), do: Validator.validate(%{dynamique: body}).files.dynamique

    defp header, do: DynamicFixtureGenerator.field_names()

    test "not UTF-8" do
      assert %{file_errors: [%{code: "encoding"}], checks: nil} = file_errors(Enum.join(header(), ",") <> "\n\xFF\n")
    end

    test "missing and unexpected columns" do
      body = Enum.join(["extra" | header() -- ["etat_pdc"]], ",") <> "\n"
      assert file_errors(body).file_errors == [%{code: "header", missing: ["etat_pdc"], unexpected: ["extra"]}]
    end

    test "columns in another order" do
      body = Enum.join(Enum.reverse(header()), ",") <> "\n"
      assert file_errors(body).file_errors == [%{code: "header_order"}]
    end

    test "semicolon delimiter" do
      body = Enum.join(header(), ";") <> "\n"

      assert file_errors(body).file_errors == [
               %{code: "header", missing: header(), unexpected: [body |> String.trim()]}
             ]
    end
  end

  test "the report is written as a manifest and Parquet files, keeping not evaluated checks" do
    dir = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    on_exit(fn -> File.rm_rf!(dir) end)
    report = valid_rows() |> put_first(:statique, "nb_pdc", nil) |> validate_rows()
    :ok = Report.write!(report, dir)

    manifest = dir |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
    statique = manifest["files"]["statique"]

    assert statique["sha256"] == report.files.statique.sha256
    assert statique["counts"]["nb_pdc:required"] == %{"errors" => 1, "not_evaluated" => 0}
    assert statique["counts"]["nb_pdc:minimum"] == %{"errors" => 0, "not_evaluated" => 1}

    assert DataFrame.from_parquet!(Path.join(dir, "statique.parquet")) |> DataFrame.to_columns() ==
             DataFrame.to_columns(report.files.statique.checks)
  end
end
