defmodule Unlock.DynamicIRVESchema do
  def schema_content do
    __ENV__.file
    |> Path.join("../../meta/schema-irve-dynamique.json")
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end

  # builds the field list based on the actual schema
  def build_schema_fields_list do
    schema_content()
    |> Map.fetch!("fields")
    |> Enum.map(fn(field) -> Map.fetch!(field, "name") end)
  end
end