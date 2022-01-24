defmodule Transport.Jobs.SingleGtfsToNetexConverterJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.SingleGtfsToNetexConverterJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "launch a NeTEx conversion" do
    permanent_url = "https://resource.fr"
    uuid = Ecto.UUID.generate()

    # add a resource history
    %{id: resource_history_id} =
      insert(:resource_history,
        payload: %{"uuid" => uuid, "format" => "GTFS", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    # mock for the resource download
    Transport.HTTPoison.Mock
    |> expect(:get!, 1, fn ^permanent_url ->
      %{status_code: 200, body: "this is my GTFS file"}
    end)

    Transport.Rambo.Mock
    # mock for the resource NeTEx conversion
    |> expect(:run, 1, fn _binary_path,
                          [
                            "--input",
                            _file_path,
                            "--output",
                            netex_folder_path,
                            "--participant",
                            "transport.data.gouv.fr"
                          ],
                          _opts ->
      file_path = Path.join([netex_folder_path, "a_file"])
      # we create a netex folder containing one file
      File.mkdir_p!(netex_folder_path)
      File.write!(file_path, "beautiful and simple netex content")
      {:ok, ""}
    end)
    # mock for the netex folder zip process
    |> expect(:run, 1, fn "zip", [zip_name, "-r", "./"], [cd: _netex_folder_path] ->
      File.write!(zip_name, "beautiful and simple zipped netex content")
      {:ok, ""}
    end)

    Transport.Test.S3TestUtils.s3_mocks_upload_file("conversions/gtfs-to-netex/")

    # job succeed
    assert :ok ==
             perform_job(SingleGtfsToNetexConverterJob, %{"resource_history_id" => resource_history_id})

    # a data_conversion row is recorded ✌️‍
    DB.DataConversion
    |> DB.Repo.get_by!(
      convert_from: "GTFS",
      convert_to: "NeTEx",
      resource_history_uuid: uuid
    )

    Transport.Test.TestUtils.ensure_no_tmp_files!("conversion_gtfs_netex_")
  end

  test "a failing NeTEx conversion" do
    permanent_url = "https://resource.fr"
    uuid = Ecto.UUID.generate()

    # add a resource history
    %{id: resource_history_id} =
      insert(:resource_history,
        payload: %{"uuid" => uuid, "format" => "GTFS", "permanent_url" => permanent_url, "filename" => "fff"}
      )

    # mock for the resource download
    Transport.HTTPoison.Mock
    |> expect(:get!, 1, fn ^permanent_url ->
      %{status_code: 200, body: "this is my GTFS file"}
    end)

    Transport.Rambo.Mock
    # mock for the resource NeTEx failing conversion
    |> expect(:run, 1, fn _binary_path,
                          [
                            "--input",
                            _file_path,
                            "--output",
                            _netex_folder_path,
                            "--participant",
                            "transport.data.gouv.fr"
                          ],
                          _opts ->
      {:error, "conversion failed"}
    end)

    # job raises an Error
    assert_raise MatchError, fn ->
      perform_job(SingleGtfsToNetexConverterJob, %{"resource_history_id" => resource_history_id})
    end

    # no data_conversion row is recorded
    assert_raise(Ecto.NoResultsError, fn ->
      DB.DataConversion
      |> DB.Repo.get_by!(
        convert_from: "GTFS",
        convert_to: "NeTEx",
        resource_history_uuid: uuid
      )
    end)

    # all temp files have been cleaned
    Transport.Test.TestUtils.ensure_no_tmp_files!("conversion_gtfs_netex_")
  end
end
