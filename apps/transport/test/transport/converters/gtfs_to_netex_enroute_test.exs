defmodule Transport.Converters.GTFSToNeTExEnRouteTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  import Mox
  alias Transport.Converters.GTFSToNeTExEnRoute

  setup :verify_on_exit!

  setup do
    {:ok, bypass: Bypass.open()}
  end

  test "create_gtfs_to_netex_conversion" do
    uuid = Ecto.UUID.generate()
    filepath = "/tmp/test"

    Transport.HTTPoison.Mock
    |> expect(:post!, fn "https://chouette-convert.enroute.mobi/api/conversions",
                         {:multipart,
                          [
                            {"type", "gtfs-netex"},
                            {"options[profile]", "french"},
                            {:file, ^filepath, {"form-data", [name: "file", filename: "test"]}, []}
                          ]},
                         [{"authorization", "Token token=fake_enroute_token"}] ->
      %HTTPoison.Response{status_code: 201, body: Jason.encode!(%{"id" => uuid})}
    end)

    assert uuid == GTFSToNeTExEnRoute.create_gtfs_to_netex_conversion(filepath)
  end

  describe "get_conversion" do
    test "success case" do
      uuid = Ecto.UUID.generate()
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{uuid}"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"id" => uuid, "status" => "success"})}}
      end)

      assert {:success, %{"id" => uuid, "status" => "success"}} == GTFSToNeTExEnRoute.get_conversion(uuid)
    end

    test "pending case" do
      uuid = Ecto.UUID.generate()
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{uuid}"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"id" => uuid, "status" => "pending"})}}
      end)

      assert {:pending, %{"id" => uuid, "status" => "pending"}} == GTFSToNeTExEnRoute.get_conversion(uuid)
    end

    test "running case" do
      uuid = Ecto.UUID.generate()
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{uuid}"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"id" => uuid, "status" => "running"})}}
      end)

      assert {:pending, %{"id" => uuid, "status" => "running"}} == GTFSToNeTExEnRoute.get_conversion(uuid)
    end

    test "failed case" do
      uuid = Ecto.UUID.generate()
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{uuid}"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"id" => uuid, "status" => "failed"})}}
      end)

      assert {:failed, %{"id" => uuid, "status" => "failed"}} == GTFSToNeTExEnRoute.get_conversion(uuid)
    end

    test "HTTP error case" do
      uuid = Ecto.UUID.generate()
      url = "https://chouette-convert.enroute.mobi/api/conversions/#{uuid}"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^url, [{"authorization", "Token token=fake_enroute_token"}] ->
        {:error, %HTTPoison.Error{}}
      end)

      assert :error = GTFSToNeTExEnRoute.get_conversion(uuid)
    end
  end

  test "download_conversion", %{bypass: bypass} do
    uuid = Ecto.UUID.generate()
    tmp_path = Path.join(System.tmp_dir!(), uuid)
    url = "#{uuid}/download"

    Process.put(:req_bypass, bypass)

    Bypass.expect_once(bypass, "GET", url, fn %Plug.Conn{} = conn ->
      assert ["Token token=fake_enroute_token"] = Plug.Conn.get_req_header(conn, "authorization")
      Plug.Conn.send_resp(conn, 200, "File content")
    end)

    refute File.exists?(tmp_path)
    assert :ok == GTFSToNeTExEnRoute.download_conversion(uuid, File.stream!(tmp_path))

    assert "File content" == File.read!(tmp_path)
    File.rm!(tmp_path)
  end
end
