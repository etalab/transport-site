defmodule DB.IRVEValidFileTest do
  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  defp insert_file!(resource_id, attrs \\ %{}) do
    DB.Repo.insert!(%DB.IRVEValidFile{
      datagouv_dataset_id: Map.get(attrs, :dataset_id, "dataset-#{resource_id}"),
      datagouv_resource_id: resource_id,
      checksum: Map.get(attrs, :checksum, "checksum-#{resource_id}"),
      dataset_title: Map.get(attrs, :dataset_title, "title-#{resource_id}"),
      datagouv_organization_or_owner: Map.get(attrs, :org, "org-#{resource_id}")
    })
  end

  describe "existing_datagouv_resource_ids/0" do
    test "returns the distinct set of datagouv_resource_ids" do
      insert_file!("resource-a")
      insert_file!("resource-b")
      # same resource, another version: must be deduplicated
      insert_file!("resource-a", %{checksum: "checksum-a-2"})

      assert DB.IRVEValidFile.existing_datagouv_resource_ids() ==
               MapSet.new(["resource-a", "resource-b"])
    end
  end

  describe "orphan_files/1" do
    test "returns metadata and PDC count for the given resource ids only" do
      content =
        DB.Factory.IRVE.to_csv_body([
          DB.Factory.IRVE.generate_row(%{"id_pdc_itinerance" => "FRPAN99E00000001"}),
          DB.Factory.IRVE.generate_row(%{"id_pdc_itinerance" => "FRPAN99E00000002"})
        ])

      {_summary, validated_df} = Transport.IRVE.Validator.validate_and_summarize(content)
      casted_df = Transport.IRVE.Processing.cast_validated_frame(validated_df)
      checksum = Transport.IRVE.DatabaseImporter.compute_checksum(content)

      Transport.IRVE.DatabaseImporter.write_to_db(
        casted_df,
        checksum,
        "orphan-dataset-id",
        "orphan-resource-id",
        "orphan-dataset-title",
        "orphan-org",
        "2024-01-01T10:00:00+00:00"
      )

      insert_file!("kept-resource-id")

      assert [orphan] = DB.IRVEValidFile.orphan_files(["orphan-resource-id"])

      assert %{
               datagouv_dataset_id: "orphan-dataset-id",
               datagouv_resource_id: "orphan-resource-id",
               dataset_title: "orphan-dataset-title",
               datagouv_organization_or_owner: "orphan-org",
               pdc_count: 2
             } = orphan

      assert DB.IRVEValidFile.orphan_files([]) == []
    end
  end
end
