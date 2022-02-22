defmodule Transport.Test.S3TestUtils do
  @moduledoc """
  Some utility functions for S3 mocks
  """
  import Mox
  require ExUnit.Assertions

  @doc """
  Returns a list of existing bucket names
  """
  def s3_mock_list_buckets(bucket_names \\ []) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn request ->
      ExUnit.Assertions.assert(
        %{
          service: :s3,
          http_method: :get,
          path: "/"
        } = request
      )

      %{body: %{buckets: bucket_names |> Enum.map(&%{name: &1})}}
    end)
  end

  def s3_mocks_upload_file(assert_path) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn %{
                              service: :s3,
                              http_method: :put,
                              path: path,
                              bucket: _bucket_name,
                              body: _content,
                              headers: %{"x-amz-acl" => "public-read"}
                            } ->
      ExUnit.Assertions.assert(path |> String.starts_with?(assert_path))
    end)
  end

  def s3_mocks_delete_object(expected_bucket, expected_path) do
    Transport.ExAWS.Mock
    |> expect(:request!, fn request ->
      ExUnit.Assertions.assert(
        %{
          service: :s3,
          http_method: :delete,
          path: ^expected_path,
          bucket: ^expected_bucket
        } = request
      )
    end)
  end
end
