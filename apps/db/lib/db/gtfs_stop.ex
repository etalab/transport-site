defmodule DB.GtfsStops do
  @moduledoc """
  This contains the information present in GTFS stops.txt files.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_stops" do
    belongs_to(:gtfs_import, DB.GtfsImport)
    field(:stop_id, :binary)
    field(:stop_name, :binary)
    field(:stop_lat, :float)
    field(:stop_lon, :float)
    field(:location_type, :binary)
  end

  def fill_stop_from_resource_history(resource_history_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    aws_s3_config = ExAws.Config.new(:s3,
      access_key_id: ["xxx", :instance_role],
      secret_access_key: ["yyy", :instance_role]
    )
    file = Unzip.S3File.new(filename, "bucket_name", aws_s3_config)
    {:ok, unzip} = Unzip.new(file)
    files = Unzip.list_entries(unzip)
  end

end


# from https://hexdocs.pm/unzip/readme.html
defmodule Unzip.S3File do
  defstruct [:path, :bucket, :s3_config]
  alias __MODULE__

  def new(path, bucket, s3_config) do
    %S3File{path: path, bucket: bucket, s3_config: s3_config}
  end
end

defimpl Unzip.FileAccess, for: Unzip.S3File do
  alias ExAws.S3

  def size(file) do
    %{headers: headers} = S3.head_object(file.bucket, file.path) |> ExAws.request!(file.s3_config)

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
