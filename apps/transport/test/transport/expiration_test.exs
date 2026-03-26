defmodule Transport.ExpirationTest do
  use ExUnit.Case, async: true
  import DB.Factory

  doctest Transport.Expiration, import: true

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "datasets_with_resources_expiring_on/1" do
    test "returns datasets with resources expiring on a specific date - GTFS",
      do: test_case("GTFS", Transport.Validators.GTFSTransport)

    test "returns datasets with resources expiring on a specific date - GTFS flex",
      do: test_case("GTFS", Transport.Validators.MobilityDataGTFSValidator)

    test "returns datasets with resources expiring on a specific date - NeTEx",
      do: test_case("NeTEx", Transport.Validators.NeTEx.Validator)

    defp test_case(format, validator) do
      {today, tomorrow, yesterday} = {Date.utc_today(), Date.add(Date.utc_today(), 1), Date.add(Date.utc_today(), -1)}
      assert [] == today |> Transport.Expiration.datasets_with_resources_expiring_on()

      insert_fn = fn %Date{} = expiration_date, %DB.Dataset{} = dataset ->
        resource = insert(:resource, dataset: dataset, format: format)
        resource_history = insert(:resource_history, resource: resource)

        multi_validation =
          insert(:multi_validation, validator: validator.validator_name(), resource_history: resource_history)

        metadata = %{"end_date" => expiration_date}
        insert(:resource_metadata, multi_validation: multi_validation, metadata: metadata)
      end

      # Ignores hidden or inactive datasets
      insert_fn.(today, insert(:dataset, is_active: false))
      insert_fn.(today, insert(:dataset, is_active: true, is_hidden: true))

      assert [] == today |> Transport.Expiration.datasets_with_resources_expiring_on()

      # 2 GTFS resources expiring on the same day for a dataset
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset, is_active: true)
      insert_fn.(today, dataset)
      insert_fn.(today, dataset)

      assert [
               {%DB.Dataset{id: ^dataset_id},
                [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
             ] = today |> Transport.Expiration.datasets_with_resources_expiring_on()

      assert [] == tomorrow |> Transport.Expiration.datasets_with_resources_expiring_on()
      assert [] == yesterday |> Transport.Expiration.datasets_with_resources_expiring_on()

      insert_fn.(tomorrow, dataset)

      assert [
               {%DB.Dataset{id: ^dataset_id},
                [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
             ] = today |> Transport.Expiration.datasets_with_resources_expiring_on()

      assert [
               {%DB.Dataset{id: ^dataset_id}, [%DB.Resource{dataset_id: ^dataset_id}]}
             ] = tomorrow |> Transport.Expiration.datasets_with_resources_expiring_on()

      assert [] == yesterday |> Transport.Expiration.datasets_with_resources_expiring_on()

      # Multiple datasets
      %DB.Dataset{id: d2_id} = d2 = insert(:dataset, is_active: true)
      insert_fn.(today, d2)

      assert [
               {%DB.Dataset{id: ^dataset_id},
                [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]},
               {%DB.Dataset{id: ^d2_id}, [%DB.Resource{dataset_id: ^d2_id}]}
             ] = today |> Transport.Expiration.datasets_with_resources_expiring_on()
    end
  end
end
