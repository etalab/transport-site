defmodule Transport.IRVE.ReportItem do
  @moduledoc """
  Quick & dirty structure to massage the processing outcome of a single
  IRVE file into a structure with all the same keys.
  (as expected by the `DataFrame` that we use to create the CSV file).
  """
  @enforce_keys [:dataset_id, :resource_id, :url, :dataset_title, :consolidation_status, :estimated_pdc_count]
  defstruct [
    :dataset_id,
    :resource_id,
    :url,
    :dataset_title,
    :datagouv_organization_or_owner,
    :datagouv_last_modified,
    :resource_status,
    :consolidation_status,
    :error_message,
    :error_type,
    :estimated_pdc_count,
    :file_extension
  ]

  def from_result({:error_occurred, error, resource}) do
    new(resource, :error_occurred, Exception.message(error), inspect(error.__struct__))
  end

  def from_result({:download_failed, resource, message}) do
    new(resource, :download_failed, message, nil)
  end

  def from_result({:file_level_errors, resource, file_level_errors}) do
    new(resource, :file_level_errors, Enum.join(file_level_errors, "\n"), nil)
  end

  def from_result({status, resource}) do
    new(resource, status, nil, nil)
  end

  # Presence relationship between data.gouv.fr and our database, from a pre-run snapshot of the
  # resource ids in the database. Kept separate from the consolidation outcome.
  def put_resource_status(%__MODULE__{resource_id: resource_id} = report_row, db_resource_ids) do
    resource_status =
      if MapSet.member?(db_resource_ids, resource_id),
        do: :on_datagouv_and_in_db,
        else: :on_datagouv_not_in_db

    %{report_row | resource_status: resource_status}
  end

  # A resource still in the database but no longer listed on data.gouv.fr: no download/processing
  # happened this run, so `consolidation_status` and the download-related fields stay nil.
  def from_orphan_file(%{
        datagouv_dataset_id: dataset_id,
        datagouv_resource_id: resource_id,
        dataset_title: dataset_title,
        datagouv_organization_or_owner: datagouv_organization_or_owner,
        datagouv_last_modified: datagouv_last_modified,
        pdc_count: pdc_count
      }) do
    %__MODULE__{
      dataset_id: dataset_id,
      resource_id: resource_id,
      url: nil,
      dataset_title: dataset_title,
      datagouv_organization_or_owner: datagouv_organization_or_owner,
      datagouv_last_modified: datagouv_last_modified,
      resource_status: :in_db_deleted_from_datagouv,
      consolidation_status: nil,
      estimated_pdc_count: pdc_count,
      error_message: nil,
      error_type: nil,
      file_extension: nil
    }
  end

  def to_map(%__MODULE__{} = report_row) do
    report_row
    |> Map.from_struct()
    |> Map.update!(:consolidation_status, &stringify/1)
    |> Map.update!(:resource_status, &stringify/1)
    |> Map.update!(:datagouv_last_modified, &stringify/1)
  end

  # `nil` (empty CSV cell) for orphan rows; keeps mixed atom/DateTime/string columns uniform.
  defp stringify(nil), do: nil
  defp stringify(value), do: to_string(value)

  defp new(resource, status, error_message, error_type) do
    %__MODULE__{
      dataset_id: resource.dataset_id,
      resource_id: resource.resource_id,
      url: resource.url,
      dataset_title: resource.dataset_title,
      datagouv_organization_or_owner: resource.datagouv_organization_or_owner,
      datagouv_last_modified: resource.datagouv_last_modified,
      consolidation_status: status,
      estimated_pdc_count: resource[:estimated_pdc_count],
      error_message: error_message,
      error_type: error_type,
      file_extension: resource[:file_extension]
    }
  end
end
