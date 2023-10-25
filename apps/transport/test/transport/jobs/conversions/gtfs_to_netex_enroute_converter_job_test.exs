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
      {uuid, conversion_uuid} = {Ecto.UUID.generate(), Ecto.UUID.generate()}
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
                 scheduled_at: %DateTime{} = scheduled_at,
                 args: %{"action" => "poll", "attempt" => 1, "data_conversion_id" => ^data_conversion_id}
               }
             ] = all_enqueued()

      assert_in_delta DateTime.diff(scheduled_at, DateTime.utc_now()), 15, 1

      # The temporary file has been deleted
      refute File.exists?(tmp_path)
    end

    test "conversion already exists" do
      %DB.ResourceHistory{} =
        resource_history =
        insert(:resource_history,
          payload: %{"uuid" => uuid = Ecto.UUID.generate(), "permanent_url" => "https://example.com"}
        )

      insert(:data_conversion,
        resource_history_uuid: uuid,
        convert_from: :GTFS,
        convert_to: :NeTEx,
        converter: GTFSToNeTExEnRouteConverterJob.converter(),
        payload: %{}
      )

      assert GTFSToNeTExEnRouteConverterJob.conversion_exists?(resource_history)

      assert {:discard, "An enroute/gtfs-to-netex conversion already exists for ResourceHistory##{resource_history.id}"} ==
               perform_job(GTFSToNeTExEnRouteConverterJob, %{
                 "action" => "create",
                 "resource_history_id" => resource_history.id
               })
    end
  end

  describe "action=poll" do
    test "discards the job if status is failed or success" do
      Enum.each([:failed, :success], fn status ->
        insert(:resource_history,
          payload: %{"uuid" => uuid = Ecto.UUID.generate(), "permanent_url" => "https://example.com"}
        )

        %DB.DataConversion{} =
          data_conversion =
          insert(:data_conversion,
            resource_history_uuid: uuid,
            convert_from: :GTFS,
            convert_to: :NeTEx,
            converter: GTFSToNeTExEnRouteConverterJob.converter(),
            payload: %{"converter" => %{"id" => Ecto.UUID.generate()}},
            status: status
          )

        assert {:discard, _} =
                 perform_job(GTFSToNeTExEnRouteConverterJob, %{
                   "action" => "poll",
                   "attempt" => 1,
                   "data_conversion_id" => data_conversion.id
                 })
      end)
    end

    test "pending case" do
      insert(:resource_history,
        payload: %{"uuid" => uuid = Ecto.UUID.generate(), "permanent_url" => "https://example.com"}
      )

      %DB.DataConversion{id: data_conversion_id} =
        data_conversion =
        insert(:data_conversion,
          resource_history_uuid: uuid,
          convert_from: :GTFS,
          convert_to: :NeTEx,
          converter: GTFSToNeTExEnRouteConverterJob.converter(),
          payload: %{"converter" => %{"id" => conversion_uuid = Ecto.UUID.generate()}},
          status: :created
        )

      # EnRoute's API response: conversion is still ongoing
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{conversion_uuid}"
      started_at = DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_iso8601()

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: Jason.encode!(%{"id" => conversion_uuid, "status" => "pending", "started_at" => started_at})
         }}
      end)

      assert :ok ==
               perform_job(GTFSToNeTExEnRouteConverterJob, %{
                 "action" => "poll",
                 "attempt" => 1,
                 "data_conversion_id" => data_conversion_id
               })

      # The DataConversion has been updated with the attempt number and metadata
      # returned by the conversion API
      assert %DB.DataConversion{
               status: :pending,
               payload: %{
                 "converter" => %{
                   "attempt" => 1,
                   "id" => ^conversion_uuid,
                   "started_at" => ^started_at,
                   "status" => "pending"
                 }
               }
             } = DB.Repo.reload!(data_conversion)

      # A job to poll again the EnRoute's API has been dispatched
      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.GTFSToNeTExEnRouteConverterJob",
                 state: "scheduled",
                 scheduled_at: %DateTime{} = scheduled_at,
                 args: %{"action" => "poll", "attempt" => 2, "data_conversion_id" => ^data_conversion_id}
               }
             ] = all_enqueued()

      assert_in_delta DateTime.diff(scheduled_at, DateTime.utc_now()), 10, 1
    end

    test "failed case" do
      insert(:resource_history,
        payload: %{"uuid" => uuid = Ecto.UUID.generate(), "permanent_url" => "https://example.com"}
      )

      %DB.DataConversion{id: data_conversion_id} =
        data_conversion =
        insert(:data_conversion,
          resource_history_uuid: uuid,
          convert_from: :GTFS,
          convert_to: :NeTEx,
          converter: GTFSToNeTExEnRouteConverterJob.converter(),
          payload: %{"converter" => %{"id" => conversion_uuid = Ecto.UUID.generate()}},
          status: :pending
        )

      # EnRoute's API response: conversion failed
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{conversion_uuid}"
      started_at = DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_iso8601()
      ended_at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601()

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "id" => conversion_uuid,
               "status" => "failed",
               "started_at" => started_at,
               "ended_at" => ended_at
             })
         }}
      end)

      assert :ok ==
               perform_job(GTFSToNeTExEnRouteConverterJob, %{
                 "action" => "poll",
                 "attempt" => 1,
                 "data_conversion_id" => data_conversion_id
               })

      # The DataConversion has been updated with the attempt number and metadata
      # returned by the conversion API
      assert %DB.DataConversion{
               status: :failed,
               payload: %{
                 "converter" => %{
                   "attempt" => 1,
                   "id" => ^conversion_uuid,
                   "started_at" => ^started_at,
                   "status" => "failed"
                 }
               }
             } = DB.Repo.reload!(data_conversion)

      assert Enum.empty?(all_enqueued())
    end

    test "success case" do
      insert(:resource_history,
        payload: %{"uuid" => uuid = Ecto.UUID.generate(), "permanent_url" => "https://example.com"}
      )

      %DB.DataConversion{id: data_conversion_id} =
        data_conversion =
        insert(:data_conversion,
          resource_history_uuid: uuid,
          convert_from: :GTFS,
          convert_to: :NeTEx,
          converter: GTFSToNeTExEnRouteConverterJob.converter(),
          payload: %{"converter" => %{"id" => conversion_uuid = Ecto.UUID.generate()}},
          status: :pending
        )

      # EnRoute's API response: conversion is done and can be downloaded
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{conversion_uuid}"
      started_at = DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_iso8601()
      ended_at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601()

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "id" => conversion_uuid,
               "status" => "success",
               "started_at" => started_at,
               "ended_at" => ended_at
             })
         }}
      end)

      assert :ok ==
               perform_job(GTFSToNeTExEnRouteConverterJob, %{
                 "action" => "poll",
                 "attempt" => 1,
                 "data_conversion_id" => data_conversion_id
               })

      # The DataConversion has been updated with the attempt number and metadata
      # returned by the conversion API
      assert %DB.DataConversion{
               status: :success,
               payload: %{
                 "converter" => %{
                   "attempt" => 1,
                   "id" => ^conversion_uuid,
                   "started_at" => ^started_at,
                   "status" => "success"
                 }
               }
             } = DB.Repo.reload!(data_conversion)

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.GTFSToNeTExEnRouteConverterJob",
                 state: "available",
                 args: %{"action" => "download", "data_conversion_id" => ^data_conversion_id}
               }
             ] = all_enqueued()
    end

    test "max attempts reached" do
      insert(:resource_history,
        payload: %{"uuid" => uuid = Ecto.UUID.generate(), "permanent_url" => "https://example.com"}
      )

      %DB.DataConversion{id: data_conversion_id} =
        data_conversion =
        insert(:data_conversion,
          resource_history_uuid: uuid,
          convert_from: :GTFS,
          convert_to: :NeTEx,
          converter: GTFSToNeTExEnRouteConverterJob.converter(),
          payload: %{"converter" => %{"id" => conversion_uuid = Ecto.UUID.generate()}},
          status: :pending
        )

      assert :ok ==
               perform_job(GTFSToNeTExEnRouteConverterJob, %{
                 "action" => "poll",
                 "attempt" => 720,
                 "data_conversion_id" => data_conversion_id
               })

      assert %DB.DataConversion{
               status: :timeout,
               payload: %{
                 "converter" => %{
                   "attempt" => 720,
                   "id" => ^conversion_uuid,
                   "stopped_at" => stopped_at_str
                 }
               }
             } = DB.Repo.reload!(data_conversion)

      assert Enum.empty?(all_enqueued())
      {:ok, stopped_at, 0} = DateTime.from_iso8601(stopped_at_str)
      assert_in_delta DateTime.diff(DateTime.utc_now(), stopped_at), 0, 1
    end
  end
end
