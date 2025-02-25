defmodule Transport.S3.AggregatesUploaderTest do
  use ExUnit.Case, async: true

  alias Transport.S3.AggregatesUploader
  alias Transport.Test.S3TestUtils
  import Mox
  setup :verify_on_exit!

  test "export to S3" do
    aggregate = "aggregate-20250127193035.csv"
    latest_aggregate = "aggregate-latest.csv"
    checksum = "#{aggregate}.sha256sum"
    latest_checksum = "#{latest_aggregate}.sha256sum"

    bucket_name = Transport.S3.bucket_name(:aggregates)

    test_data = "some relevant data"

    # Compute this with sha256sum: echo -n "some relevant data" | sha256sum
    expected_sha256 = "28d89bc28c02b0ed66f22b400b535e800e3a6b305e931c18dc01f8bf3582f1f9"

    S3TestUtils.s3_mock_stream_file(path: aggregate, bucket: bucket_name, acl: :private, file_content: test_data)
    S3TestUtils.s3_mock_stream_file(path: checksum, bucket: bucket_name, acl: :private, file_content: expected_sha256)
    S3TestUtils.s3_mocks_remote_copy_file(bucket_name, aggregate, latest_aggregate)
    S3TestUtils.s3_mocks_remote_copy_file(bucket_name, checksum, latest_checksum)

    AggregatesUploader.with_tmp_file(fn file ->
      File.write(file, test_data)

      :ok = AggregatesUploader.upload_aggregate!(file, aggregate, latest_aggregate)
    end)
  end
end
