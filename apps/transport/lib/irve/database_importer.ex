defmodule Transport.IRVE.DatabaseImporter do
  @moduledoc """
  A module to import validated IRVE files and their PDC into the database.

  There are two ways to use this module, either through `try_write_uncasted_df/3` (entry point for the consolidation)
  or through its main function `write_to_db/7`.

  Importing the same `(resource_id, checksum)` again raises a unique-constraint error.

  When you import a new version of an existing file (same resource_id but different checksum),
  it will insert a new file (different record ID) and its PDCs, then delete the previous file and its PDCs
  inside a single transaction.
  """

  import Ecto.Query

  # the default timeout on `insert_all` is not enough when importing large files (e.g. Qualicharge)
  # with this module, so we override it. It is important, as a consequence, to avoid calling this
  # too many times in parallel, since it would exhaust the Ecto connection pool.
  @import_timeout 90_000

  # return:
  # - `:import_successful` if the import went fine
  # - `:already_in_db` if the same content (based on file checksum) is in db for
  #     the provided combination of ids
  # (else raise an error)
  def try_write_untyped_df(untyped_df, checksum, %{
        dataset_id: datagouv_dataset_id,
        resource_id: datagouv_resource_id,
        dataset_title: dataset_title,
        datagouv_organization_or_owner: datagouv_organization_or_owner,
        datagouv_last_modified: datagouv_last_modified
      }) do
    typed_df = Transport.IRVE.Processing.cast_validated_frame(untyped_df)

    write_to_db(
      typed_df,
      checksum,
      datagouv_dataset_id,
      datagouv_resource_id,
      dataset_title,
      datagouv_organization_or_owner,
      datagouv_last_modified
    )

    :import_successful
  rescue
    e in [Ecto.ConstraintError] ->
      if e.type == :unique && e.constraint == "irve_valid_file_datagouv_resource_id_checksum_index" do
        :already_in_db
      else
        reraise(e, __STACKTRACE__)
      end
  end

  def write_to_db(
        typed_df,
        checksum,
        datagouv_dataset_id,
        datagouv_resource_id,
        dataset_title,
        datagouv_organization_or_owner,
        datagouv_last_modified
      ) do
    rows_stream = Explorer.DataFrame.to_rows_stream(typed_df)

    DB.Repo.transaction(
      fn ->
        # This may raise an error if we try to insert a duplicate (same datagouv_resource_id and checksum)
        # which is fine, the caller should handle it.
        %DB.IRVEValidFile{id: file_id} =
          write_new_file!(
            datagouv_dataset_id,
            datagouv_resource_id,
            checksum,
            dataset_title,
            datagouv_organization_or_owner,
            datagouv_last_modified
          )

        write_pdcs(rows_stream, file_id)
        # Eventually try to erase previous file, which cascades on delete on PDCs.
        delete_previous_file_and_pdcs(datagouv_dataset_id, datagouv_resource_id, checksum)
      end,
      timeout: @import_timeout
    )
  end

  def compute_checksum(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  @doc """
  True if a file with this exact content (same `datagouv_resource_id` and `checksum`) is already stored.

  Lets the consolidation skip validating and inserting content that hasn't changed since the last run.
  """
  def already_in_db?(datagouv_resource_id, checksum) do
    DB.IRVEValidFile
    |> where(datagouv_resource_id: ^datagouv_resource_id, checksum: ^checksum)
    |> DB.Repo.exists?()
  end

  defp write_new_file!(
         datagouv_dataset_id,
         datagouv_resource_id,
         checksum,
         dataset_title,
         datagouv_organization_or_owner,
         datagouv_last_modified
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    file_data = %DB.IRVEValidFile{
      datagouv_dataset_id: datagouv_dataset_id,
      datagouv_resource_id: datagouv_resource_id,
      checksum: checksum,
      dataset_title: dataset_title,
      datagouv_organization_or_owner: datagouv_organization_or_owner,
      datagouv_last_modified: parse_datetime(datagouv_last_modified),
      inserted_at: now,
      updated_at: now
    }

    DB.Repo.insert!(file_data, returning: [:id])
  end

  # Similar implementation than Transport.ImportData.parse_datetime/1
  defp parse_datetime(date) when is_binary(date) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(date)

    # Can’t use :utc_datetime_usec in the schema
    # because some datagouv resources do not have ms precision in the last_modified field,
    # which would make the import fail with errors like:
    # :utc_datetime_usec expects microsecond precision, got: ~U[2026-01-01 03:01:19Z]"
    # It works fine working with changesets (aka all good on DB.Resource/Dataset)
    # but we’re directly inserting with `insert_all` here.
    # See https://elixirforum.com/t/upgrading-to-ecto-3-anyway-to-easily-deal-with-usec-it-complains-with-or-without-usec/22137/7
    DateTime.truncate(datetime, :second)
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

  defp delete_previous_file_and_pdcs(datagouv_dataset_id, datagouv_resource_id, checksum) do
    from(f in DB.IRVEValidFile,
      where:
        f.datagouv_dataset_id == ^datagouv_dataset_id and f.datagouv_resource_id == ^datagouv_resource_id and
          f.checksum != ^checksum
    )
    # The PDCs are deleted by the foreign key constraint with on_delete: :delete_all
    |> DB.Repo.delete_all()
  end
end
