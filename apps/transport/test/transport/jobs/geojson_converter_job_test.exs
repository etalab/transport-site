defmodule Transport.Test.Transport.Jobs.GeojsonConverterJobTest do
  use ExUnit.Case
  import DB.Factory
  import Mox

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "Geojson conversion" do
    test "a simple successful case" do
      %{id: resource_id} = insert(:resource, url: "resource_url")

      Unlock.HTTP.Client.Mock
      |> expect(:get!, 1, fn url, opts ->
        assert(url == "resource_url")
        assert(opts == [])
        %{status: 200, body: "this is my file"}
      end)

      Transport.RamboLauncher.Mock
      |> expect(:run, 1, fn binary_path, opts ->
        assert(["--input", file_path] = opts)
        {:ok, "this my geojson content"}
      end)

      job_id = 33
      assert :ok == Transport.GeojsonConverterJob.perform(%{id: job_id, args: %{"resource_id" => resource_id}})

      result_path = System.tmp_dir!() |> Path.join("#{job_id}_output.geojson")
      assert result_path |> File.exists?()
      File.rm!(result_path)
    end
  end
end
