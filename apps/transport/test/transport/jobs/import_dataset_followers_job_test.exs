defmodule Transport.Test.Transport.Jobs.ImportDatasetFollowersJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportDatasetFollowersJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    insert(:dataset, is_active: false)
    dataset = insert(:dataset)
    other_dataset = insert(:dataset)
    not_found_dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    %DB.Contact{id: other_contact_id} = other_contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    insert(:dataset_follower, dataset: dataset, contact: contact, source: :datagouv)

    setup_http_responses([
      {dataset,
       %{
         data: [
           %{"follower" => %{"id" => contact.datagouv_user_id}},
           %{"follower" => %{"id" => Ecto.UUID.generate()}}
         ],
         status_code: 200
       }},
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
    [%DB.Contact{id: id1}, %DB.Contact{id: id2}] = dataset_followers(other_dataset)
    assert MapSet.new([id1, id2]) == MapSet.new([contact_id, other_contact_id])
  end

  defp dataset_followers(%DB.Dataset{} = dataset), do: dataset |> DB.Repo.preload(:followers) |> Map.fetch!(:followers)

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
