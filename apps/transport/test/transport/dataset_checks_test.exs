defmodule Transport.DatasetChecksTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "check" do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)
    %DB.Resource{id: r1_id} = insert(:resource, dataset: dataset, is_available: false)
    insert(:resource, dataset: dataset, is_available: true)

    %{resource: %{id: r3_id}, multi_validation: %{id: mv1_id}} =
      insert_resource_and_friends(Date.utc_today(), dataset: dataset)

    %{resource: %{id: r4_id}, multi_validation: %{id: mv2_id}} =
      insert_resource_and_friends(Date.add(Date.utc_today(), 10), dataset: dataset, max_error: "Error")

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, fn ^organization_id, [restrict_fields: true] ->
      {:ok, %{"members" => [%{"user" => %{"id" => contact.datagouv_user_id}}]}}
    end)

    discussion = %{
      "closed" => nil,
      "discussion" => [
        %{"posted_on" => DateTime.utc_now() |> DateTime.to_iso8601(), "posted_by" => %{"id" => Ecto.UUID.generate()}}
      ]
    }

    Datagouvfr.Client.Discussions.Mock |> expect(:get, fn ^datagouv_id -> [discussion] end)

    result = Transport.DatasetChecks.check(dataset)

    assert %{
             unavailable_resource: [%DB.Resource{id: ^r1_id, is_available: false}],
             expiring_resource: [{%DB.Resource{id: ^r3_id}, [%DB.MultiValidation{id: ^mv1_id}]}],
             invalid_resource: [
               {%DB.Resource{id: ^r4_id},
                [%DB.MultiValidation{id: ^mv2_id, digest: %{"max_severity" => %{"max_level" => "Error"}}}]}
             ],
             unanswered_discussions: [^discussion]
           } = result

    assert Transport.DatasetChecks.count_issues(result) == 4
  end

  test "issue_name" do
    dataset = insert(:dataset)

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, fn _organization_id, [restrict_fields: true] -> {:ok, %{"members" => []}} end)

    Datagouvfr.Client.Discussions.Mock |> expect(:get, fn _datagouv_id -> [] end)

    Transport.DatasetChecks.check(dataset)
    |> Map.keys()
    |> Enum.each(&Transport.DatasetChecks.issue_name/1)
  end

  test "invalid_resource for a GTFS-RT" do
    dataset = insert(:dataset)
    resource = insert(:resource, dataset: dataset)

    too_few_errors = [
      %{"error_id" => "E003", "errors_count" => 10},
      %{"error_id" => "E004", "errors_count" => 20},
      %{"error_id" => "E011", "errors_count" => 10}
    ]

    errors = too_few_errors ++ [%{"error_id" => "E034", "errors_count" => 10}]

    mv1 = %DB.MultiValidation{
      validator: Transport.Validators.GTFSRT.validator_name(),
      result: %{"errors" => too_few_errors}
    }

    mv2 = %{mv1 | result: %{"errors" => errors}}

    dataset = dataset |> DB.Repo.preload(:resources)

    assert [] == dataset |> Transport.DatasetChecks.invalid_resource(%{resource.id => [mv1]})
    assert [{_, [^mv2]}] = dataset |> Transport.DatasetChecks.invalid_resource(%{resource.id => [mv2]})
  end

  test "has_issues?/1 and count_issues/1" do
    d1 = insert(:dataset)
    d2 = insert(:dataset)
    insert(:resource, dataset: d2, is_available: false)

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, 2, fn _organization_id, [restrict_fields: true] -> {:ok, %{"members" => []}} end)

    Datagouvfr.Client.Discussions.Mock |> expect(:get, 2, fn _datagouv_id -> [] end)

    result = Transport.DatasetChecks.check(d1)
    refute result |> Transport.DatasetChecks.has_issues?()
    assert Transport.DatasetChecks.count_issues(result) == 0

    result = Transport.DatasetChecks.check(d2)
    assert result |> Transport.DatasetChecks.has_issues?()
    assert Transport.DatasetChecks.count_issues(result) == 1
  end

  test "unanswered_discussions" do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    %DB.Dataset{organization_id: organization_id, datagouv_id: datagouv_id} = dataset = insert(:dataset)

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, fn ^organization_id, [restrict_fields: true] ->
      {:ok, %{"members" => [%{"user" => %{"id" => contact.datagouv_user_id}}]}}
    end)

    discussion_by_contact = %{
      "closed" => nil,
      "discussion" => [
        %{
          "posted_on" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "posted_by" => %{"id" => contact.datagouv_user_id}
        }
      ]
    }

    discussion_too_old = %{
      "closed" => nil,
      "discussion" => [
        %{
          "posted_on" => DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.to_iso8601(),
          "posted_by" => %{"id" => Ecto.UUID.generate()}
        }
      ]
    }

    unanswered_discussion = %{
      "closed" => nil,
      "discussion" => [
        %{
          "posted_on" => DateTime.utc_now() |> DateTime.add(-20, :day) |> DateTime.to_iso8601(),
          "posted_by" => %{"id" => Ecto.UUID.generate()}
        }
      ]
    }

    closed_discussion = %{unanswered_discussion | "closed" => DateTime.utc_now() |> DateTime.to_iso8601()}

    Datagouvfr.Client.Discussions.Mock
    |> expect(:get, fn ^datagouv_id ->
      [
        discussion_by_contact,
        discussion_too_old,
        unanswered_discussion,
        closed_discussion
      ]
    end)

    assert Transport.DatasetChecks.recent_discussion?(discussion_by_contact)
    assert Transport.DatasetChecks.recent_discussion?(unanswered_discussion)
    refute Transport.DatasetChecks.recent_discussion?(discussion_too_old)

    assert Transport.DatasetChecks.answered_by_team_member(discussion_by_contact, [contact.datagouv_user_id])
    refute Transport.DatasetChecks.answered_by_team_member(discussion_too_old, [contact.datagouv_user_id])
    refute Transport.DatasetChecks.answered_by_team_member(unanswered_discussion, [contact.datagouv_user_id])

    assert [unanswered_discussion] == Transport.DatasetChecks.unanswered_discussions(dataset)
  end
end
