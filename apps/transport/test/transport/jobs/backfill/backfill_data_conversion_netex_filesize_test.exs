defmodule Transport.Jobs.Backfill.DataConversionNeTExFilesizeTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.Backfill.DataConversionNeTExFilesize
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "perform" do
    data_conversion =
      insert(:data_conversion, %{
        convert_to: "NeTEx",
        convert_from: "GTFS",
        resource_history_uuid: Ecto.UUID.generate(),
        payload: %{"permanent_url" => url = "https//example.com", "filesize" => 1, "other_field" => "other_value"}
      })

    # Ignored because it's a conversion GTFS > GeoJSON
    insert(:data_conversion, %{
      convert_to: "GeoJSON",
      convert_from: "GTFS",
      resource_history_uuid: Ecto.UUID.generate(),
      payload: %{}
    })

    %{id: next_data_conversion} =
      insert(:data_conversion, %{
        convert_to: "NeTEx",
        convert_from: "GTFS",
        resource_history_uuid: Ecto.UUID.generate(),
        payload: %{}
      })

    size = "1000"
    size_int = String.to_integer(size)

    expect(Transport.HTTPoison.Mock, :head, 1, fn ^url ->
      {:ok, %{headers: [{"coucou", "toi"}, {"content-length", size}]}}
    end)

    assert {:ok,
            %Oban.Job{
              state: "scheduled",
              queue: "default",
              worker: "Transport.Jobs.Backfill.DataConversionNeTExFilesize",
              args: %{backfill: true, data_conversion_id: ^next_data_conversion}
            }} =
             perform_job(DataConversionNeTExFilesize, %{"data_conversion_id" => data_conversion.id, "backfill" => true})

    assert %DB.DataConversion{
             payload: %{
               "permanent_url" => ^url,
               "filesize" => ^size_int,
               "other_field" => "other_value"
             }
           } = DB.Repo.reload!(data_conversion)

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.Backfill.DataConversionNeTExFilesize",
               args: %{"backfill" => true, "data_conversion_id" => ^next_data_conversion}
             }
           ] = all_enqueued()
  end
end
