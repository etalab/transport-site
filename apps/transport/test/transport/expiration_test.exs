defmodule Transport.ExpirationTest do
  use ExUnit.Case, async: true
  import DB.Factory

  doctest Transport.Expiration, import: true

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "datasets_with_resources_expiring_on/1" do
    test "returns datasets with resources expiring on a specific date" do
      {today, tomorrow, yesterday} = {Date.utc_today(), Date.add(Date.utc_today(), 1), Date.add(Date.utc_today(), -1)}
      assert [] == today |> Transport.Expiration.datasets_with_resources_expiring_on()

      insert_fn = fn %Date{} = expiration_date, %DB.Dataset{} = dataset ->
        multi_validation =
          insert(:multi_validation,
            validator: Transport.Validators.GTFSTransport.validator_name(),
            resource_history: insert(:resource_history, resource: insert(:resource, dataset: dataset, format: "GTFS"))
          )

        insert(:resource_metadata,
          multi_validation_id: multi_validation.id,
          metadata: %{"end_date" => expiration_date}
        )
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

    test "works with both GTFS validators" do
      today = Date.utc_today()
      a_week_ago = Date.add(today, -7)

      %{dataset: %DB.Dataset{id: d1_id}} = insert_resource_and_friends(today)

      %DB.Dataset{id: d2_id} = insert(:dataset)
      resource = insert(:resource, dataset_id: d2_id, format: "GTFS")
      resource_history = insert(:resource_history, resource: resource)

      insert(:multi_validation,
        resource_history: resource_history,
        validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
        metadata: %DB.ResourceMetadata{metadata: %{"start_date" => a_week_ago, "end_date" => a_week_ago}}
      )

      assert [{%DB.Dataset{id: ^d1_id}, _}] =
               Transport.Expiration.datasets_with_resources_expiring_on(today)

      assert [{%DB.Dataset{id: ^d2_id}, _}] =
               Transport.Expiration.datasets_with_resources_expiring_on(a_week_ago)
    end
  end
end
