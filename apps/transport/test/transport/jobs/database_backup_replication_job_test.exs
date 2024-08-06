defmodule Transport.Test.Transport.Jobs.DatabaseBackupReplicationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import Mox
  alias Transport.Jobs.DatabaseBackupReplicationJob
  doctest DatabaseBackupReplicationJob, import: true

  setup :verify_on_exit!
  @source_bucket_name "fake_source_bucket_name"
  @destination_bucket_name "fake_destination_bucket_name"

  test "test config is up to date" do
    assert @source_bucket_name == Application.fetch_env!(:ex_aws, :database_backup_source)[:bucket_name]
    assert @destination_bucket_name == Application.fetch_env!(:ex_aws, :database_backup_destination)[:bucket_name]
  end

  test "check_dump_not_too_large!" do
    assert DatabaseBackupReplicationJob.max_size_threshold() == DatabaseBackupReplicationJob.gigabytes(10)
    DatabaseBackupReplicationJob.check_dump_not_too_large!(%{size: "1"})

    oversize = DatabaseBackupReplicationJob.gigabytes(11)
    assert oversize > DatabaseBackupReplicationJob.max_size_threshold()

    assert_raise RuntimeError, ~r'^Latest database dump is larger than 10 gigabytes', fn ->
      DatabaseBackupReplicationJob.check_dump_not_too_large!(%{size: oversize |> round() |> to_string()})
    end
  end

  test "check_dump_is_recent_enough!" do
    assert DatabaseBackupReplicationJob.recent_enough_threshold() == DatabaseBackupReplicationJob.hours_in_seconds(12)

    recent_datetime =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-1 * DatabaseBackupReplicationJob.hours_in_seconds(2), :second)

    DatabaseBackupReplicationJob.check_dump_is_recent_enough!(%{
      last_modified: recent_datetime |> NaiveDateTime.to_iso8601()
    })

    too_old =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(-1 * DatabaseBackupReplicationJob.hours_in_seconds(13), :second)

    assert_raise RuntimeError, ~r'^Latest database dump is not recent enough', fn ->
      DatabaseBackupReplicationJob.check_dump_is_recent_enough!(%{last_modified: too_old |> NaiveDateTime.to_iso8601()})
    end
  end

  test "latest_dump and latest_source_dumps" do
    # List objects in source bucket
    Transport.ExAWS.Mock
    |> expect(:request!, 2, fn operation, config ->
      assert %ExAws.Operation.S3{
               body: "",
               bucket: @source_bucket_name,
               http_method: :get,
               path: "/",
               resource: "",
               service: :s3
             } = operation

      assert config_is_source?(config)

      recent_datetime = NaiveDateTime.utc_now() |> NaiveDateTime.add(-60 * 60 * 2, :second)
      older_datetime = recent_datetime |> NaiveDateTime.add(-60 * 60 * 10, :second)

      %{
        body: %{
          contents: [
            %{last_modified: older_datetime |> NaiveDateTime.to_iso8601(), key: "second", size: "100"},
            %{last_modified: recent_datetime |> NaiveDateTime.to_iso8601(), key: "first", size: "200"}
          ]
        }
      }
    end)

    assert [%{key: "first", size: "200"}, %{key: "second", size: "100"}] =
             DatabaseBackupReplicationJob.latest_source_dumps(3)

    assert %{key: "first", size: "200"} = DatabaseBackupReplicationJob.latest_dump()
  end

  test "bucket_name" do
    assert DatabaseBackupReplicationJob.bucket_name(:source) == @source_bucket_name
    assert DatabaseBackupReplicationJob.bucket_name(:destination) == @destination_bucket_name
  end

  test "perform" do
    latest_dump_filename = Ecto.UUID.generate() <> ".dump"

    setup_mock_permissions_checks()

    # List objects in source bucket
    Transport.ExAWS.Mock
    |> expect(:request!, 2, fn operation, config ->
      assert %ExAws.Operation.S3{
               body: "",
               bucket: @source_bucket_name,
               http_method: :get,
               path: "/",
               resource: "",
               service: :s3
             } = operation

      assert config_is_source?(config)

      recent_datetime = NaiveDateTime.utc_now() |> NaiveDateTime.add(-60 * 60 * 2, :second)
      older_datetime = recent_datetime |> NaiveDateTime.add(-60 * 60 * 10, :second)

      %{
        body: %{
          contents: [
            %{last_modified: older_datetime |> NaiveDateTime.to_iso8601(), key: Ecto.UUID.generate(), size: "195"},
            %{last_modified: recent_datetime |> NaiveDateTime.to_iso8601(), key: latest_dump_filename, size: "200"}
          ]
        }
      }
    end)

    # Downloading the most recent dump
    Transport.ExAWS.Mock
    |> expect(:request!, fn operation, config ->
      assert %ExAws.S3.Download{bucket: @source_bucket_name, path: ^latest_dump_filename, service: :s3} = operation

      assert config_is_source?(config)
    end)

    # Uploading the most recent dump
    Transport.ExAWS.Mock
    |> expect(:request!, fn operation, config ->
      assert %ExAws.S3.Upload{
               bucket: @destination_bucket_name,
               path: path,
               service: :s3,
               opts: [acl: :private, timeout: 90_000],
               src: %File.Stream{}
             } = operation

      assert String.starts_with?(path, latest_dump_filename |> String.replace_trailing(".dump", ""))
      assert String.ends_with?(path, ".dump")
      assert config_is_destination?(config)
    end)

    assert :ok == perform_job(DatabaseBackupReplicationJob, %{})
  end

  test "raises if the latest dump is too small" do
    setup_mock_permissions_checks()

    # List objects in source bucket
    Transport.ExAWS.Mock
    |> expect(:request!, fn operation, config ->
      assert %ExAws.Operation.S3{
               body: "",
               bucket: @source_bucket_name,
               http_method: :get,
               path: "/",
               resource: "",
               service: :s3
             } = operation

      assert config_is_source?(config)

      recent_datetime = NaiveDateTime.utc_now() |> NaiveDateTime.add(-60 * 60 * 2, :second)
      older_datetime = recent_datetime |> NaiveDateTime.add(-60 * 60 * 10, :second)

      %{
        body: %{
          contents: [
            %{last_modified: older_datetime |> NaiveDateTime.to_iso8601(), key: Ecto.UUID.generate(), size: "100"},
            %{last_modified: recent_datetime |> NaiveDateTime.to_iso8601(), key: Ecto.UUID.generate(), size: "89"}
          ]
        }
      }
    end)

    ExUnit.CaptureLog.capture_log(fn ->
      assert_raise RuntimeError, "Latest backup size is unexpected. Yesterday: 89, today: 100", fn ->
        perform_job(DatabaseBackupReplicationJob, %{})
      end
    end)
  end

  test "check_appropriate_size!" do
    [
      {100, 91, :ok},
      {100, 109, :ok},
      {100, 88, :raise},
      {100, 112, :raise}
    ]
    |> Enum.each(fn {yesterday_size, today_size, expected} ->
      expect(Transport.ExAWS.Mock, :request!, fn operation, config ->
        assert %ExAws.Operation.S3{
                 body: "",
                 bucket: @source_bucket_name,
                 http_method: :get,
                 path: "/",
                 resource: "",
                 service: :s3
               } = operation

        assert config_is_source?(config)

        recent_datetime = NaiveDateTime.utc_now() |> NaiveDateTime.add(-60 * 60 * 2, :second)
        older_datetime = recent_datetime |> NaiveDateTime.add(-60 * 60 * 10, :second)

        %{
          body: %{
            contents: [
              %{
                last_modified: older_datetime |> NaiveDateTime.to_iso8601(),
                key: Ecto.UUID.generate(),
                size: to_string(yesterday_size)
              },
              %{
                last_modified: recent_datetime |> NaiveDateTime.to_iso8601(),
                key: Ecto.UUID.generate(),
                size: to_string(today_size)
              }
            ]
          }
        }
      end)

      case expected do
        :ok ->
          DatabaseBackupReplicationJob.check_appropriate_size!()

        :raise ->
          assert_raise RuntimeError, ~r"^Latest backup size is unexpected.", fn ->
            DatabaseBackupReplicationJob.check_appropriate_size!()
          end
      end
    end)
  end

  test "email on failure tag is set" do
    expected_tag = Transport.Jobs.ObanLogger.email_on_failure_tag()
    assert %Ecto.Changeset{params: %{"tags" => [^expected_tag]}} = DatabaseBackupReplicationJob.new(%{})
  end

  defp setup_mock_permissions_checks do
    # Listing buckets in destination
    Transport.ExAWS.Mock
    |> expect(:request!, fn operation, config ->
      assert %ExAws.Operation.S3{body: "", bucket: "", http_method: :get, path: "/", resource: "", service: :s3} =
               operation

      assert config_is_destination?(config)
      %{body: %{buckets: []}}
    end)

    # Listing objects in destination bucket
    Transport.ExAWS.Mock
    |> expect(:request, fn operation, config ->
      assert %ExAws.Operation.S3{
               body: "",
               bucket: @destination_bucket_name,
               http_method: :get,
               path: "/",
               resource: "",
               service: :s3
             } = operation

      assert config_is_destination?(config)
      {:error, {:http_error, 403, %{}}}
    end)

    # Trying to remove an object in destination bucket
    Transport.ExAWS.Mock
    |> expect(:request, fn operation, config ->
      assert %ExAws.Operation.S3{
               body: "",
               bucket: @destination_bucket_name,
               http_method: :delete,
               path: path,
               resource: "",
               service: :s3
             } = operation

      refute is_nil(path) or path == "/"
      assert config_is_destination?(config)
      {:error, {:http_error, 403, %{}}}
    end)
  end

  defp config_is_destination?(%{bucket_name: bucket_name}), do: bucket_name == @destination_bucket_name
  defp config_is_source?(%{bucket_name: bucket_name}), do: bucket_name == @source_bucket_name
end
