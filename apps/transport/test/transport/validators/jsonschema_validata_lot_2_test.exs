defmodule Transport.Validators.ValidataLot2Test do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  alias Transport.Validators.EXJSONSchema

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "test data is up to date" do
    job_id = Ecto.UUID.generate()

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 4, fn ->
      %{
        "etalab/schema_name" => %{
          "versions" => [
            %{
              "version_name" => "schema_version",
              "schema_url" => "schema_url"
            }
          ]
        }
      }
    end)

    Transport.HTTPoison.Mock
    |> expect(:post, 1, fn _url, "" ->
      {:ok,
       %HTTPoison.Response{
         status_code: 201,
         body: job_id
       }}
    end)

    poll_url = "https://json.validator.validata.fr/job/#{job_id}"

    Transport.HTTPoison.Mock
    |> expect(:get, 1, fn ^poll_url ->
      {:ok,
       %HTTPoison.Response{
         status_code: 303
       }}
    end)

    output_url = poll_url <> "/output"

    Transport.HTTPoison.Mock
    |> expect(:get, 1, fn ^output_url ->
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: "{\"validated\": true}"
       }}
    end)

    rh =
      insert(:resource_history,
        payload: %{
          "permanent_url" => "permananent_url",
          "schema_name" => "etalab/schema_name",
          "schema_version" => "schema_version"
        }
      )

    assert :ok = Transport.Validators.ValidataLot2.validate_and_save(rh)
    mv = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: rh.id)

    assert mv.validator == Transport.Validators.ValidataLot2.validator_name()
    assert mv.result == %{"validated" => true}
    assert mv.resource_history_id == rh.id
  end
end
