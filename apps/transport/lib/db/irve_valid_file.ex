defmodule DB.IRVEValidFile do
  @moduledoc """
  IRVE file that has been validated and stored. This file refers to a datagouv resource and dataset
  that is not imported on transport.data.gouv, so no reference to the dataset/resource tables.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "irve_valid_file" do
    field(:datagouv_dataset_id, :string, null: false)
    field(:datagouv_resource_id, :string, null: false)
    field(:checksum, :string, null: false)
    field(:dataset_title, :string)
    field(:datagouv_organization_or_owner, :string)
    field(:datagouv_last_modified, :utc_datetime)
    has_many(:irve_valid_pdcs, DB.IRVEValidPDC, foreign_key: :irve_valid_file_id)
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Set of `{datagouv_resource_id, checksum}` pairs currently present in the database. Meant to be
  snapshotted before a consolidation run, to tell (without an extra per-resource query) whether a
  datagouv resource already had a version imported and whether its exact content is already stored.
  """
  def existing_datagouv_resource_ids_and_checksums do
    DB.IRVEValidFile
    |> select([f], {f.datagouv_resource_id, f.checksum})
    |> DB.Repo.all()
    |> MapSet.new()
  end

  @doc """
  File-level metadata and stored PDC count, for the given (typically orphan) `datagouv_resource_id`s.
  Used to report resources still in the database but no longer listed on data.gouv.fr.
  """
  def orphan_files(datagouv_resource_ids) do
    DB.IRVEValidFile
    |> where([f], f.datagouv_resource_id in ^datagouv_resource_ids)
    |> join(:left, [f], p in DB.IRVEValidPDC, on: p.irve_valid_file_id == f.id)
    |> group_by([f], f.id)
    |> select([f, p], %{
      datagouv_dataset_id: f.datagouv_dataset_id,
      datagouv_resource_id: f.datagouv_resource_id,
      dataset_title: f.dataset_title,
      datagouv_organization_or_owner: f.datagouv_organization_or_owner,
      datagouv_last_modified: f.datagouv_last_modified,
      pdc_count: count(p.id)
    })
    |> DB.Repo.all()
  end
end
