defmodule Transport.IRVE.DatabaseImporter do
  @moduledoc """
  A module to import IRVE data files and their PDC into the database, through it’s main function `write_to_db/3`.
  This function assumes you have a path to a valid IRVE data file stored on the disk (e.g. temp folder).
  It also assumes that you have checked that you haven’t imported yet this exact version of the file before.
  If you try to import the same version again (same resource_id and checksum), it will raise an error.
  When you import a new version of an existing file (same resource_id but different checksum), inside the same transaction,
  it will insert a new file (different record ID) and it’s PDCs, then delete the previous file and its PDCs.
  """

  import Ecto.Query

  # the default timeout on `insert_all` is not enough when importing large files (e.g. Qualicharge)
  # with this module, so we override it. It is important, as a consequence, to avoid calling this
  # too many times in parallel, since it would exhaust the Ecto connection pool.
  @import_timeout 60_000

  # return:
  # - `:import_successful` if the import went fine
  # - `:already_in_db` if the same content (based on file checksum) is in db for
  #     the provided combination of ids
  # (else raise an error)
  def try_write_to_db(file_path, dataset_datagouv_id, resource_datagouv_id) do
    write_to_db(file_path, dataset_datagouv_id, resource_datagouv_id)
    :import_successful
  rescue
    e in [Ecto.ConstraintError] ->
      if e.type == :unique && e.constraint == "irve_valid_file_resource_datagouv_id_checksum_index" do
        :already_in_db
      else
        reraise(e, __STACKTRACE__)
      end
  end

  def write_to_db(file_path, dataset_datagouv_id, resource_datagouv_id) do
    content = File.read!(file_path)

    rows_stream =
      content |> Transport.IRVE.Processing.read_as_data_frame() |> Explorer.DataFrame.to_rows_stream()

    checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    DB.Repo.transaction(
      fn ->
        # This may raise an error if we try to insert a duplicate (same resource_datagouv_id and checksum)
        # which is fine, the caller should handle it.
        %DB.IRVEValidFile{id: file_id} = write_new_file!(dataset_datagouv_id, resource_datagouv_id, checksum)
        write_pdcs(rows_stream, file_id)
        # Eventually try to erase previous file, which cascades on delete on PDCs.
        delete_previous_file_and_pdcs(dataset_datagouv_id, resource_datagouv_id, checksum)
      end,
      timeout: @import_timeout
    )
  end

  defp write_new_file!(dataset_datagouv_id, resource_datagouv_id, checksum) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    file_data = %DB.IRVEValidFile{
      dataset_datagouv_id: dataset_datagouv_id,
      resource_datagouv_id: resource_datagouv_id,
      checksum: checksum,
      inserted_at: now,
      updated_at: now
    }

    DB.Repo.insert!(file_data, returning: [:id])
  end

  defp write_pdcs(rows_stream, file_id) do
    rows_stream
    |> Stream.map(&DB.IRVEValidPDC.raw_data_to_schema/1)
    |> Stream.map(&Map.put(&1, :irve_valid_file_id, file_id))
    |> Stream.map(&DB.IRVEValidPDC.insert_timestamps/1)
    |> Stream.chunk_every(1000)
    |> Stream.each(fn chunk ->
      DB.Repo.insert_all(DB.IRVEValidPDC, chunk)
    end)
    |> Stream.run()
  end

  defp delete_previous_file_and_pdcs(dataset_datagouv_id, resource_datagouv_id, checksum) do
    from(f in DB.IRVEValidFile,
      where:
        f.dataset_datagouv_id == ^dataset_datagouv_id and f.resource_datagouv_id == ^resource_datagouv_id and
          f.checksum != ^checksum
    )
    # The PDCs are deleted by the foreign key constraint with on_delete: :delete_all
    |> DB.Repo.delete_all()
  end
end
