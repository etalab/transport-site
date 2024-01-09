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

  def s3_mocks_delete_object(expected_bucket, expected_path) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn request ->
      assert(request.service == :s3)
      assert(request.http_method == :delete)
      assert(request.path == expected_path)
      assert(request.bucket == expected_bucket)
    end)
  end
end
