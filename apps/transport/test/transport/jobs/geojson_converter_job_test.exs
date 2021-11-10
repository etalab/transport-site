defmodule Transport.Test.Transport.Jobs.GeojsonConverterJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  describe "Geojson conversion" do
    test "a simple successful case" do
      %{id: resource_id} = insert(:resource, url: "resource_url")

      Unlock.HTTP.Client.Mock
      |> expect(:get!, 1, fn url, opts ->
        assert(url == "resource_url")
        assert(opts == [])
        %{status: 200, body: "this is my file"}
      end)

      job_id = 33
      geojson_file_path = System.tmp_dir!() |> Path.join("#{job_id}_output.geojson")

      Transport.Rambo.Mock
      |> expect(:run, 1, fn _binary_path, opts ->
        assert(["--input", file_path, "--output", geojson_file_path] = opts)
        {:ok, "this my geojson content"}
      end)

      assert :ok == Transport.GeojsonConverterJob.perform(%{id: job_id, args: %{"resource_id" => resource_id}})
    end
  end
end
