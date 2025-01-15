defmodule Transport.Test.S3TestUtils do
  @moduledoc """
  Some utility functions for S3 mocks
  """
  import Mox
  import ExUnit.Assertions

  @doc """
  Returns a list of existing bucket names
  """
  def s3_mock_list_buckets(bucket_names \\ []) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn request ->
      assert(request.service == :s3)
      assert(request.http_method == :get)
      assert(request.path == "/")

      %{body: %{buckets: bucket_names |> Enum.map(&%{name: &1})}}
    end)
  end

  def s3_mock_stream_file(start_path: expected_start_path, bucket: expected_bucket) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn %ExAws.S3.Upload{
                              src: %File.Stream{},
                              bucket: ^expected_bucket,
                              path: path,
                              opts: [acl: :public_read],
                              service: :s3
                            } ->
      assert String.starts_with?(path, expected_start_path)
    end)
  end

  def s3_mock_stream_file(
        path: expected_path,
        bucket: expected_bucket,
        acl: expected_acl,
        file_content: expected_file_content
      ) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn %ExAws.S3.Upload{
                              src: src = %File.Stream{},
                              bucket: ^expected_bucket,
                              path: ^expected_path,
                              opts: [acl: ^expected_acl],
                              service: :s3
                            } ->
      assert src |> Enum.join("\n") == expected_file_content
      :ok
    end)
  end

  def s3_mocks_delete_object(expected_bucket, expected_path) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn %ExAws.Operation.S3{
                              bucket: ^expected_bucket,
                              path: ^expected_path,
                              http_method: :delete,
                              service: :s3
                            } ->
      :ok
    end)
  end

  def s3_mocks_remote_copy_file(expected_bucket, expected_src_path, expected_dest_path) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn %ExAws.Operation.S3{
                              bucket: ^expected_bucket,
                              path: ^expected_dest_path,
                              http_method: :put,
                              service: :s3,
                              headers: headers
                            } ->
      assert Map.get(headers, "x-amz-copy-source") =~ "/#{expected_bucket}/#{expected_src_path}"
      %{body: %{}}
    end)
  end
end
