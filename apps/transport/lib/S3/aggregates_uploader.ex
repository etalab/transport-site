defmodule Transport.S3.AggregatesUploader do
  @moduledoc """
  Helpers to upload a file, computes its sha256, and update a "latest" file.
  """

  @spec upload_aggregate!(Path.t(), String.t(), String.t()) :: :ok
  @doc """
  This method takes a local `file` and upload 4 different files to our S3 `aggregates` bucket (the bucket is expected to exist):
  - the `remote_path` and `remote_latest_path` containing the data from `file`
  - two companions files with `.sha256sum` extension appended (SHA256 sum is computed on the fly)
  
  Example

    with_tmp_file(fn file ->
      File.write(file, "some relevant data")
      upload_aggregate!(file, "aggregate-20250127193035.csv", "aggregate-latest.csv")
    end)
  """
  def upload_aggregate!(file, remote_path, remote_latest_path) do
    with_tmp_file(fn checksum_file ->
      sha256!(file, checksum_file)

      upload_files!(file, checksum_file, remote_path)
      |> update_latest_files!(remote_latest_path)
    end)
  end

  @spec with_tmp_file((Path.t() -> any())) :: any()
  def with_tmp_file(cb) do
    file = mk_tmp_file()

    try do
      cb.(file)
    after
      :ok = File.rm(file)
    end
  end

  defp mk_tmp_file do
    path = System.tmp_dir!() |> Path.join(Ecto.UUID.generate())

    File.touch!(path)

    path
  end

  defp sha256!(file, checksum_file) do
    hash_state = :crypto.hash_init(:sha256)

    hash =
      File.stream!(file, 2048)
      |> Enum.reduce(hash_state, fn chunk, prev_state ->
        :crypto.hash_update(prev_state, chunk)
      end)
      |> :crypto.hash_final()
      |> Base.encode16()
      |> String.downcase()

    File.write!(checksum_file, hash)
  end

  defp upload_files!(file, checksum_file, remote_path) do
    remote_checksum_path = checksum_filename(remote_path)

    stream_upload!(file, remote_path)
    stream_upload!(checksum_file, remote_checksum_path)

    {remote_path, remote_checksum_path}
  end

  defp update_latest_files!({remote_path, remote_checksum_path}, remote_latest_path) do
    remote_latest_checksum_path = checksum_filename(remote_latest_path)

    copy!(remote_path, remote_latest_path)
    copy!(remote_checksum_path, remote_latest_checksum_path)

    :ok
  end

  defp checksum_filename(base_filename) do
    "#{base_filename}.sha256sum"
  end

  defp stream_upload!(file, filename) do
    Transport.S3.stream_to_s3!(:aggregates, file, filename)
  end

  defp copy!(s3_path, filename) do
    Transport.S3.remote_copy_file!(:aggregates, s3_path, filename)
  end
end
