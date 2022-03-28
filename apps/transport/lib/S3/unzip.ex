defmodule Transport.Unzip.S3File do
  @moduledoc """
  Read a remote zip file stored on a S3 bucket, as explained here
  https://hexdocs.pm/unzip/readme.html
  """

  defstruct [:path, :bucket, :s3_config]
  alias __MODULE__

  def new(path, bucket, s3_config) do
    %S3File{path: path, bucket: bucket, s3_config: s3_config}
  end

  def get_file_stream(file_name, zip_name, bucket_name) do
    aws_s3_config =
      ExAws.Config.new(:s3,
        access_key_id: [Application.fetch_env!(:ex_aws, :access_key_id), :instance_role],
        secret_access_key: [Application.fetch_env!(:ex_aws, :secret_access_key), :instance_role]
      )

    file = new(zip_name, bucket_name, aws_s3_config)
    {:ok, unzip} = Unzip.new(file)
    Unzip.file_stream!(unzip, file_name)
  end
end

defimpl Unzip.FileAccess, for: Transport.Unzip.S3File do
  alias ExAws.S3

  def size(file) do
    %{headers: headers} = file.bucket |> S3.head_object(file.path) |> ExAws.request!(file.s3_config)

    size =
      headers
      |> Enum.find(fn {k, _} -> String.downcase(k) == "content-length" end)
      |> elem(1)
      |> String.to_integer()

    {:ok, size}
  end

  def pread(file, offset, length) do
    {_, chunk} =
      S3.Download.get_chunk(
        %S3.Download{bucket: file.bucket, path: file.path, dest: nil},
        %{start_byte: offset, end_byte: offset + length - 1},
        file.s3_config
      )

    {:ok, chunk}
  end
end
