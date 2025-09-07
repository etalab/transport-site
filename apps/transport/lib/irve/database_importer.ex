defmodule Transport.IRVE.DatabaseImporter do
  @moduledoc """
  A module to import IRVE data files and their PDC into the database.
  It assumes you have a path to a valid IRVE data file.
  """

  import Ecto.Query

  def write_to_db(file_path, dataset_datagouv_id, resource_datagouv_id) do
    {:ok, content} = File.read(file_path)

    rows =
      content |> Transport.IRVE.Processing.read_as_data_frame() |> Explorer.DataFrame.to_rows()

    #  Note for review: may chose another way to get a checksum
    # See Transport.S3.AggregatesUploader sha256! private function
    checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    previous_version = get_previous_file(dataset_datagouv_id, resource_datagouv_id)

    case previous_version do
      #  If previous version exists and checksum is the same, do nothing.
      %DB.IRVEValidFile{checksum: ^checksum} ->
        :no_change

      # If there is no previous version, insert one. Then insert all PDCs.
      nil ->
        DB.Repo.transaction(fn ->
          {:ok, %DB.IRVEValidFile{id: file_id}} = write_new_file(dataset_datagouv_id, resource_datagouv_id, checksum)
          write_pdcs(rows, file_id)
        end)

      # If previous version exists but checksum is different, update it, then delete all PDCs and reinsert them.
      %DB.IRVEValidFile{} ->
        DB.Repo.transaction(fn ->
          {:ok, %DB.IRVEValidFile{id: file_id}} = update_file(previous_version, checksum)
          # Note for review: we have to delete previous PDCS before as there is no version identifier
          # Should we rather keep a hash column in case things go wrong?
          delete_previous_pdcs(file_id)
          write_pdcs(rows, file_id)
        end)
    end
  end

  defp write_new_file(dataset_datagouv_id, resource_datagouv_id, checksum) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    file_data = %DB.IRVEValidFile{
      dataset_datagouv_id: dataset_datagouv_id,
      resource_datagouv_id: resource_datagouv_id,
      checksum: checksum,
      inserted_at: now,
      updated_at: now
    }

    DB.Repo.insert(file_data, returning: [:id])
  end

  defp get_previous_file(dataset_datagouv_id, resource_datagouv_id) do
    DB.IRVEValidFile
    |> where([f], f.dataset_datagouv_id == ^dataset_datagouv_id and f.resource_datagouv_id == ^resource_datagouv_id)
    |> DB.Repo.one()
  end

  defp update_file(%DB.IRVEValidFile{} = previous_file, checksum) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    changeset =
      Ecto.Changeset.change(previous_file,
        checksum: checksum,
        updated_at: now
      )

    DB.Repo.update(changeset, returning: [:id])
  end

  defp write_pdcs(rows, file_id) do
    rows
    |> Enum.map(&DB.IRVEValidPDC.raw_data_to_schema/1)
    |> Enum.map(&Map.put(&1, :irve_valid_file_id, file_id))
    |> Enum.map(&insert_timestamps/1)
    |> Stream.chunk_every(1000)
    |> Stream.each(fn chunk ->
      DB.Repo.insert_all(DB.IRVEValidPDC, chunk)
    end)
    |> Stream.run()
  end

  defp insert_timestamps(map) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    map
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp delete_previous_pdcs(file_id) do
    from(p in DB.IRVEValidPDC, where: p.irve_valid_file_id == ^file_id)
    |> DB.Repo.delete_all()
  end
end
