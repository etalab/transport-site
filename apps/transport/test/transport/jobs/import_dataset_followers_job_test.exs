defmodule Transport.Test.Transport.Jobs.ImportDatasetFollowersJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.ImportDatasetFollowersJob

  setup :verify_on_exit!

  setup do
    # Using the real implementation for the moment, and then it fallsback on HTTPoison.Mock
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    insert(:dataset, is_active: false)
    producer_org = :organization |> build() |> Map.from_struct()
    other_org = :organization |> build() |> Map.from_struct()
    dataset = insert(:dataset, organization_id: producer_org.id)
    other_dataset = insert(:dataset)
    not_found_dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    %DB.Contact{id: other_contact_id} =
      other_contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate(), organizations: [other_org]})

    contact_producer = insert_contact(%{datagouv_user_id: Ecto.UUID.generate(), organizations: [producer_org]})

    insert(:dataset_follower, dataset: dataset, contact: contact, source: :datagouv)

    setup_http_responses([
      {
        dataset,
        # Should only create a DatasetFollower row for `contact`:
        # - 2nd follower is not a known contact
        # - `contact_producer` is a member of the dataset organization and we don't create rows for producers
        %{
          data: [
            %{"follower" => %{"id" => contact.datagouv_user_id}},
            %{"follower" => %{"id" => Ecto.UUID.generate()}},
            %{"follower" => %{"id" => contact_producer.datagouv_user_id}}
          ],
          status_code: 200
        }
      },
      {
        other_dataset,
        %{
          data: [
            %{"follower" => %{"id" => other_contact.datagouv_user_id}},
            %{"follower" => %{"id" => contact.datagouv_user_id}}
          ],
          status_code: 200
        }
      },
      {not_found_dataset, %{data: "", status_code: 404}}
    ])

    assert [%DB.Contact{id: ^contact_id}] = dataset_followers(dataset)
    assert [] = dataset_followers(other_dataset)

    assert :ok == perform_job(ImportDatasetFollowersJob, %{})

    assert [%DB.Contact{id: ^contact_id}] = dataset_followers(dataset)
    assert [%DB.Contact{id: ^contact_id}, %DB.Contact{id: ^other_contact_id}] = dataset_followers(other_dataset)
  end

  test "deletes producers following their datasets" do
    producer_org = :organization |> build() |> Map.from_struct()
    dataset = insert(:dataset, organization_id: producer_org.id)
    other_dataset = insert(:dataset)
    %DB.Contact{id: producer_id} = producer = insert_contact(%{organizations: [producer_org]})

    insert(:dataset_follower, dataset: dataset, contact: producer, source: :datagouv)
    insert(:dataset_follower, dataset: other_dataset, contact: producer, source: :datagouv)

    setup_http_responses([
      {
        dataset,
        %{
          data: [%{"follower" => %{"id" => Ecto.UUID.generate()}}],
          status_code: 200
        }
      },
      {
        other_dataset,
        %{
          data: [%{"follower" => %{"id" => Ecto.UUID.generate()}}],
          status_code: 200
        }
      }
    ])

    assert :ok == perform_job(ImportDatasetFollowersJob, %{})

    assert [] == dataset_followers(dataset)
    assert [%DB.Contact{id: ^producer_id}] = dataset_followers(other_dataset)
  end

  test "delete_producers_following_their_datasets" do
    producer_org = :organization |> build() |> Map.from_struct()
    other_org = :organization |> build() |> Map.from_struct()
    dataset = insert(:dataset, organization_id: producer_org.id)
    other_dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact()
    %DB.Contact{id: other_contact_id} = other_contact = insert_contact(%{organizations: [other_org]})
    %DB.Contact{id: producer_id} = contact_producer = insert_contact(%{organizations: [producer_org]})

    Enum.each([dataset, other_dataset], fn current_dataset ->
      insert(:dataset_follower, dataset: current_dataset, contact: contact, source: :datagouv)
      insert(:dataset_follower, dataset: current_dataset, contact: other_contact, source: :datagouv)
      insert(:dataset_follower, dataset: current_dataset, contact: contact_producer, source: :datagouv)
    end)

    ImportDatasetFollowersJob.delete_producers_following_their_datasets()

    assert [%DB.Contact{id: ^contact_id}, %DB.Contact{id: ^other_contact_id}] = dataset_followers(dataset)

    assert [%DB.Contact{id: ^contact_id}, %DB.Contact{id: ^other_contact_id}, %DB.Contact{id: ^producer_id}] =
             dataset_followers(other_dataset)
  end

  test "contact_is_producer?" do
    refute ImportDatasetFollowersJob.contact_is_producer?({"foo", %{organization_ids: []}}, %DB.Dataset{
             organization_id: nil
           })

    refute ImportDatasetFollowersJob.contact_is_producer?({"foo", %{organization_ids: []}}, %DB.Dataset{
             organization_id: "bar"
           })

    refute ImportDatasetFollowersJob.contact_is_producer?({"foo", %{organization_ids: ["baz"]}}, %DB.Dataset{
             organization_id: "bar"
           })

    assert ImportDatasetFollowersJob.contact_is_producer?({"foo", %{organization_ids: ["bar"]}}, %DB.Dataset{
             organization_id: "bar"
           })
  end

  defp dataset_followers(%DB.Dataset{} = dataset) do
    dataset |> DB.Repo.preload(:followers, force: true) |> Map.fetch!(:followers) |> Enum.sort_by(& &1.id)
  end

  defp setup_http_responses(data) do
    responses =
      Map.new(data, fn {%DB.Dataset{datagouv_id: datagouv_id}, %{data: _, status_code: _} = params} ->
        url = "https://demo.data.gouv.fr/api/1/datasets/#{datagouv_id}/followers/?page_size=500"
        {url, params}
      end)

    Transport.HTTPoison.Mock
    |> expect(:request, Enum.count(responses), fn :get,
                                                  request_url,
                                                  "",
                                                  [{"x-fields", "data{follower{id}}, next_page"}],
                                                  [follow_redirect: true] ->
      %{status_code: status_code, data: data} = Map.fetch!(responses, request_url)
      {:ok, %HTTPoison.Response{status_code: status_code, body: Jason.encode!(%{"data" => data, "next_page" => nil})}}
    end)
  end
end
