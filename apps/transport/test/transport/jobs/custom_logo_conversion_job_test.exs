defmodule Transport.Test.Transport.Jobs.CustomLogoConversionJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.CustomLogoConversionJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    %DB.Dataset{datagouv_id: datagouv_id} = dataset = insert(:dataset)
    remote_path = "#{Ecto.UUID.generate()}.png"
    local_path = Path.join(System.tmp_dir!(), remote_path)

    logo_filename = "#{datagouv_id}.png"
    full_logo_filename = "#{datagouv_id}_full.png"

    Transport.ExAWS.Mock
    |> expect(:request!, fn %ExAws.S3.Download{
                              bucket: "transport-data-gouv-fr-logos-test",
                              path: ^remote_path,
                              dest: ^local_path,
                              opts: [],
                              service: :s3
                            } ->
      File.cp!("#{__DIR__}/../../fixture/files/logo.png", local_path)
      :ok
    end)

    Transport.ExAWS.Mock
    |> expect(:request!, 2, fn %ExAws.S3.Upload{
                                 src: %File.Stream{},
                                 bucket: "transport-data-gouv-fr-logos-test",
                                 path: path,
                                 opts: [cache_control: "public, max-age=604800", acl: :public_read],
                                 service: :s3
                               } ->
      assert Enum.member?([logo_filename, full_logo_filename], path)
    end)

    Transport.Test.S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:logos), remote_path)

    assert :ok == perform_job(CustomLogoConversionJob, %{"datagouv_id" => datagouv_id, "path" => remote_path})

    refute File.exists?(local_path)
    expected_logo_url = Transport.S3.permanent_url(:logos, logo_filename)
    expected_full_logo_url = Transport.S3.permanent_url(:logos, full_logo_filename)

    assert %DB.Dataset{custom_logo: ^expected_logo_url, custom_full_logo: ^expected_full_logo_url} =
             DB.Repo.reload!(dataset)
  end
end
