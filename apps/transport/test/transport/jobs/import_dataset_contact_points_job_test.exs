defmodule Transport.Test.Transport.Jobs.ImportDatasetContactPointsJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportDatasetContactPointsJob

  doctest ImportDatasetContactPointsJob, import: true

  @producer_reasons Transport.NotificationReason.subscribable_reasons_related_to_datasets(:producer)

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "import_contact_point" do
    test "removes a previously existing contact point" do
      other_producer = insert_contact()
      contact_point = insert_contact()
      %DB.Dataset{datagouv_id: datagouv_id} = dataset = insert(:dataset)

      other_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: other_producer.id,
          role: :producer,
          reason: :expiration,
          source: :user
        )

      contact_point_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: contact_point.id,
          role: :producer,
          reason: :expiration,
          source: :"automation:import_contact_point"
        )

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^datagouv_id -> {:ok, %{"contact_points" => []}} end)

      ImportDatasetContactPointsJob.import_contact_point(datagouv_id)

      # The contact point's subscription has been deleted and the other one
      # is untouched.
      assert [other_ns, nil] == DB.Repo.reload([other_ns, contact_point_ns])

      # The contact point still exists
      refute DB.Repo.reload(contact_point) |> is_nil()
    end

    test "removes contact point with nothing in the database" do
      other_producer = insert_contact()
      %DB.Dataset{datagouv_id: datagouv_id} = dataset = insert(:dataset)

      other_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: other_producer.id,
          role: :producer,
          reason: :expiration,
          source: :user
        )

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^datagouv_id -> {:ok, %{"contact_points" => []}} end)

      ImportDatasetContactPointsJob.import_contact_point(datagouv_id)

      assert other_ns == DB.Repo.reload(other_ns)
    end

    test "creates producer subscriptions for an existing contact with a subscription" do
      %DB.Contact{id: contact_id} = contact_point = insert_contact()
      %DB.Dataset{datagouv_id: datagouv_id, id: dataset_id} = dataset = insert(:dataset)

      insert(:notification_subscription,
        dataset_id: dataset.id,
        contact_id: contact_point.id,
        role: :producer,
        reason: :expiration,
        source: :user
      )

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^datagouv_id ->
        {:ok,
         %{"contact_points" => [%{"email" => contact_point.email, "name" => DB.Contact.display_name(contact_point)}]}}
      end)

      ImportDatasetContactPointsJob.import_contact_point(datagouv_id)

      assert MapSet.new(@producer_reasons) ==
               DB.NotificationSubscription.base_query()
               |> where(
                 [notification_subscription: ns],
                 ns.dataset_id == ^dataset_id and ns.role == :producer and ns.contact_id == ^contact_id
               )
               |> select([notification_subscription: ns], ns.reason)
               |> DB.Repo.all()
               |> MapSet.new()

      assert [
               %{count: Enum.count(@producer_reasons) - 1, source: :"automation:import_contact_point"},
               %{count: 1, source: :user}
             ] ==
               DB.NotificationSubscription.base_query()
               |> where(
                 [notification_subscription: ns],
                 ns.dataset_id == ^dataset_id and ns.role == :producer and ns.contact_id == ^contact_id
               )
               |> select([notification_subscription: ns], %{source: ns.source, count: count(ns.id)})
               |> group_by([notification_subscription: ns], ns.source)
               |> DB.Repo.all()
    end

    test "creates a new contact and producer subscriptions, deletes the previous contact point subscriptions" do
      %DB.Dataset{datagouv_id: datagouv_id} = dataset = insert(:dataset)
      previous_contact_point = insert_contact()

      previous_contact_point_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: previous_contact_point.id,
          role: :producer,
          reason: :expiration,
          source: :"automation:import_contact_point"
        )

      email = "john@example.fr"

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^datagouv_id ->
        {:ok, %{"contact_points" => [%{"email" => email, "name" => "John DOE"}]}}
      end)

      ImportDatasetContactPointsJob.import_contact_point(datagouv_id)

      %DB.Contact{first_name: "John", email: ^email, creation_source: :"automation:import_contact_point"} =
        contact = DB.Repo.get_by(DB.Contact, last_name: "DOE")

      assert nil == DB.Repo.reload(previous_contact_point_ns)
      assert MapSet.new(@producer_reasons) == subscribed_reasons(dataset, contact)
    end

    test "creates subscriptions for 2 contact points, deletes the previous contact point subscription" do
      %DB.Dataset{datagouv_id: datagouv_id} = dataset = insert(:dataset)
      previous_contact_point = insert_contact()

      previous_contact_point_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: previous_contact_point.id,
          role: :producer,
          reason: :expiration,
          source: :"automation:import_contact_point"
        )

      john_email = "john@example.fr"
      jane_email = "jane@example.fr"

      Datagouvfr.Client.Datasets.Mock
      |> expect(:get, 1, fn ^datagouv_id ->
        {:ok,
         %{
           "contact_points" => [
             %{"email" => john_email, "name" => "John DOE"},
             %{"email" => jane_email, "name" => "Jane FOO"}
           ]
         }}
      end)

      ImportDatasetContactPointsJob.import_contact_point(datagouv_id)

      %DB.Contact{first_name: "John", email: ^john_email, creation_source: :"automation:import_contact_point"} =
        john = DB.Repo.get_by(DB.Contact, last_name: "DOE")

      %DB.Contact{first_name: "Jane", email: ^jane_email, creation_source: :"automation:import_contact_point"} =
        jane = DB.Repo.get_by(DB.Contact, last_name: "FOO")

      assert nil == DB.Repo.reload(previous_contact_point_ns)
      assert MapSet.new(@producer_reasons) == subscribed_reasons(dataset, john)
      assert MapSet.new(@producer_reasons) == subscribed_reasons(dataset, jane)
    end
  end

  test "perform" do
    %DB.Dataset{datagouv_id: d1_datagouv_id} = d1 = insert(:dataset)
    %DB.Dataset{datagouv_id: d2_datagouv_id} = d2 = insert(:dataset)
    contact_point = insert_contact()
    email = "john@example.com"
    insert(:dataset, is_active: false)
    insert(:dataset, is_active: true, is_hidden: true)

    assert MapSet.new([d1_datagouv_id, d2_datagouv_id]) ==
             ImportDatasetContactPointsJob.dataset_datagouv_ids() |> MapSet.new()

    setup_http_responses([
      {d1_datagouv_id,
       %{"contact_points" => [%{"email" => contact_point.email, "name" => DB.Contact.display_name(contact_point)}]}},
      {d2_datagouv_id, %{"contact_points" => [%{"email" => email, "name" => "DOE John"}]}}
    ])

    assert :ok == perform_job(ImportDatasetContactPointsJob, %{})

    %DB.Contact{email: ^email, first_name: "John", creation_source: :"automation:import_contact_point"} =
      created_contact = DB.Repo.get_by(DB.Contact, last_name: "DOE")

    assert MapSet.new(@producer_reasons) == subscribed_reasons(d1, contact_point)
    assert MapSet.new([]) == subscribed_reasons(d2, contact_point)

    assert MapSet.new(@producer_reasons) == subscribed_reasons(d2, created_contact)
    assert MapSet.new([]) == subscribed_reasons(d1, created_contact)
  end

  defp subscribed_reasons(%DB.Dataset{id: dataset_id}, %DB.Contact{id: contact_id}) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.dataset_id == ^dataset_id and ns.role == :producer and ns.contact_id == ^contact_id and
        ns.source == :"automation:import_contact_point"
    )
    |> select([notification_subscription: ns], ns.reason)
    |> DB.Repo.all()
    |> MapSet.new()
  end

  defp setup_http_responses(data) when is_list(data) do
    responses =
      Enum.into(data, %{}, fn {datagouv_id, response} ->
        {datagouv_id, response}
      end)

    # HTTP requests order is not important
    Datagouvfr.Client.Datasets.Mock
    |> expect(:get, Enum.count(responses), fn datagouv_id ->
      {:ok, Map.fetch!(responses, datagouv_id)}
    end)
  end
end
