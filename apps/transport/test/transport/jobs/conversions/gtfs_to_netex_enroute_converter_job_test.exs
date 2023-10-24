defmodule Transport.Test.Transport.Jobs.GTFSToNeTExEnRouteConverterJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.GTFSToNeTExEnRouteConverterJob

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    {:ok, bypass: Bypass.open()}
  end

  describe "action=create" do
    test "success case", %{bypass: bypass} do
      uuid = Ecto.UUID.generate()
      conversion_uuid = Ecto.UUID.generate()
      permanent_url = "http://localhost:#{bypass.port}/#{uuid}"

      %DB.ResourceHistory{id: resource_history_id} =
        resource_history =
        insert(:resource_history,
          payload: %{"uuid" => uuid, "permanent_url" => permanent_url}
        )

      # ResourceHistory is downloaded and streamed to the disk
      Bypass.expect_once(bypass, "GET", permanent_url |> URI.new!() |> Map.fetch!(:path), fn %Plug.Conn{} = conn ->
        Plug.Conn.send_resp(conn, 200, "File content")
      end)

      tmp_path = GTFSToNeTExEnRouteConverterJob.tmp_path(resource_history)

      # The file content is sent to the EnRoute's API
      Transport.HTTPoison.Mock
      |> expect(:post!, fn "https://chouette-convert.enroute.mobi/api/conversions",
                           {:multipart,
                            [
                              {"type", "gtfs-netex"},
                              {"options[profile]", "french"},
                              {:file, ^tmp_path, {"form-data", [name: "file", filename: _]}, []}
                            ]},
                           [{"authorization", "Token token=fake_enroute_token"}] ->
        %HTTPoison.Response{status_code: 201, body: Jason.encode!(%{"id" => conversion_uuid})}
      end)

      refute GTFSToNeTExEnRouteConverterJob.conversion_exists?(resource_history)

      assert :ok ==
               perform_job(GTFSToNeTExEnRouteConverterJob, %{
                 "action" => "create",
                 "resource_history_id" => resource_history_id
               })

      # A DataConversion has been recorded in the database
      assert %DB.DataConversion{
               id: data_conversion_id,
               payload: %{"converter" => %{"id" => ^conversion_uuid}},
               converter: "enroute/gtfs-to-netex",
               status: :created,
               convert_from: :GTFS,
               convert_to: :NeTEx
             } = DB.DataConversion |> DB.Repo.one!()

      assert GTFSToNeTExEnRouteConverterJob.conversion_exists?(resource_history)

      # A job to poll the EnRoute's API has been dispatched
      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.GTFSToNeTExEnRouteConverterJob",
                 state: "scheduled",
                 args: %{"action" => "poll", "attempt" => 1, "data_conversion_id" => ^data_conversion_id}
               }
             ] = all_enqueued()

      # The temporary file has been deleted
      refute File.exists?(tmp_path)
    end
  end
end
