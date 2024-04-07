defmodule Unlock.DynamicIRVESchema do
  # builds the field list based on the actual schema
  def build_schema_fields_list do
    __ENV__.file
    |> Path.join("../../meta/schema-irve-dynamique.json")
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("fields")
    |> Enum.map(fn(field) -> Map.fetch!(field, "name") end)
  end
end
