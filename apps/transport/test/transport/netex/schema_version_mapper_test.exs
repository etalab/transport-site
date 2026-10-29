defmodule Transport.NeTEx.SchemaVersionMapperTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.SchemaVersionMapper

  describe "xsd_version_for_date/1" do
    test "returns v1.3.2 for dates before June 2027" do
      assert SchemaVersionMapper.xsd_version_for_date(~D[2024-01-01]) == "v1.3.2"
      assert SchemaVersionMapper.xsd_version_for_date(~D[2025-06-15]) == "v1.3.2"
      assert SchemaVersionMapper.xsd_version_for_date(~D[2026-12-31]) == "v1.3.2"
    end

    test "returns v1.3.2 for the day before June 2027" do
      assert SchemaVersionMapper.xsd_version_for_date(~D[2027-05-31]) == "v1.3.2"
    end

    test "returns v2.0.0 for June 2027 and beyond" do
      assert SchemaVersionMapper.xsd_version_for_date(~D[2027-06-01]) == "v2.0.0"
      assert SchemaVersionMapper.xsd_version_for_date(~D[2027-12-31]) == "v2.0.0"
      assert SchemaVersionMapper.xsd_version_for_date(~D[2030-01-01]) == "v2.0.0"
    end
  end
end
