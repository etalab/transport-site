defmodule Transport.ZipProbeTest do
  use ExUnit.Case, async: true
  doctest Transport.ZipProbe, import: true

  describe "nested_zip_content?/2" do
    test "returns false for non-ZIP content inside a ZIP" do
      ZipCreator.with_tmp_zip([{"resource.xml", "<PublicationDelivery />"}], fn tmp_path ->
        zip = Unzip.LocalFile.open(tmp_path)
        {:ok, unzip} = Unzip.new(zip)

        assert Transport.ZipProbe.nested_zip_content?(unzip, "resource.xml") == false

        Unzip.LocalFile.close(zip)
      end)
    end

    test "returns true for a ZIP entry inside another ZIP" do
      ZipCreator.with_tmp_zip([{"resource.xml", "<PublicationDelivery />"}], fn inner_path ->
        inner_content = File.read!(inner_path)

        ZipCreator.with_tmp_zip([{"payload.XML", inner_content}], fn outer_path ->
          zip = Unzip.LocalFile.open(outer_path)
          {:ok, unzip} = Unzip.new(zip)

          assert Transport.ZipProbe.nested_zip_content?(unzip, "payload.XML") == true

          Unzip.LocalFile.close(zip)
        end)
      end)
    end

    test "returns false when the entry does not exist" do
      ZipCreator.with_tmp_zip([{"resource.xml", "<data />"}], fn tmp_path ->
        zip = Unzip.LocalFile.open(tmp_path)
        {:ok, unzip} = Unzip.new(zip)

        assert Transport.ZipProbe.nested_zip_content?(unzip, "nonexistent.txt") == false

        Unzip.LocalFile.close(zip)
      end)
    end
  end
end
