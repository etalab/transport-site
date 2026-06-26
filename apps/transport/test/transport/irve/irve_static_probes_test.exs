defmodule Transport.IRVE.Static.ProbesTest do
  use ExUnit.Case, async: true
  doctest Transport.IRVE.Static.Probes, import: true

  alias Transport.IRVE.Static.Probes

  defp valid_body, do: [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()

  describe "file_level_errors/2" do
    test "returns [] for a valid CSV body" do
      assert Probes.file_level_errors(valid_body(), ".csv") == []
    end

    test "accepts an empty extension" do
      assert Probes.file_level_errors(valid_body(), "") == []
    end

    test "accepts a semicolon separator" do
      body =
        [DB.Factory.IRVE.generate_row()]
        |> CSV.encode(separator: ?;, headers: true)
        |> Enum.join()

      assert Probes.file_level_errors(body, ".csv") == []
    end

    test "flags a ZIP file" do
      assert Probes.file_level_errors("PK\x03\x04" <> "some content", ".csv") ==
               ["the content is likely to be a zip file, not uncompressed CSV data"]
    end

    test "flags a non-CSV extension" do
      assert Probes.file_level_errors("non-csv-content", ".pdf") ==
               ["the content is likely not a CSV file (extension is .pdf)"]
    end

    test "flags a v1 schema file" do
      body =
        [
          DB.Factory.IRVE.generate_row()
          |> Map.put("n_operateur", "Opérateur de Charge")
          |> Map.delete("nom_operateur")
        ]
        |> DB.Factory.IRVE.to_csv_body()

      assert Probes.file_level_errors(body, ".csv") == ["looks like a v1 irve"]
    end

    test "flags a file without id_pdc_itinerance" do
      body =
        [
          DB.Factory.IRVE.generate_row()
          |> Map.put("id_pdc", "FRPAN99E12345678")
          |> Map.delete("id_pdc_itinerance")
        ]
        |> DB.Factory.IRVE.to_csv_body()

      assert Probes.file_level_errors(body, ".csv") == ["content has no id_pdc_itinerance in first line"]
    end

    test "flags an unsupported (tab) separator" do
      body =
        [DB.Factory.IRVE.generate_row()]
        |> CSV.encode(separator: ?\t, delimiter: "\n", headers: true)
        |> Enum.join()

      assert Probes.file_level_errors(body, ".csv") == ["unsupported column separator \t"]
    end

    test "does not raise when the separator cannot be hinted, returns the message instead" do
      assert [message] = Probes.file_level_errors("id_pdc_itinerance\nFRPAN99E12345678", ".csv")
      assert message =~ "could not hint header separator"
    end
  end

  describe "run_cheap_blocking_checks/2 (raising shim)" do
    test "returns :ok for a valid body" do
      assert Probes.run_cheap_blocking_checks(valid_body(), ".csv") == :ok
    end

    test "raises the first file-level error" do
      assert_raise RuntimeError, "the content is likely to be a zip file, not uncompressed CSV data", fn ->
        Probes.run_cheap_blocking_checks("PK\x03\x04" <> "some content", ".csv")
      end
    end
  end
end
