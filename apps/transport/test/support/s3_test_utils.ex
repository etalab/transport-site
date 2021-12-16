defmodule Transport.Test.S3TestUtils do
  @moduledoc """
  Some utility functions for S3 mocks
  """
  import Mox
  require ExUnit.Assertions

  def s3_mocks_create_bucket do
    Transport.ExAWS.Mock
    # Listing buckets
    |> expect(:request!, fn request ->
      ExUnit.Assertions.assert(
        %{
          service: :s3,
          http_method: :get,
          path: "/"
        } = request
      )

      %{body: %{buckets: []}}
    end)

    Transport.ExAWS.Mock
    # Bucket creation
    |> expect(:request!, fn request ->
      bucket_name = Transport.S3.bucket_name(:history)

      ExUnit.Assertions.assert(
        %{
          service: :s3,
          http_method: :put,
          path: "/",
          bucket: ^bucket_name,
          headers: %{"x-amz-acl" => "public-read"}
        } = request
      )
    end)
  end
end
