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

  def to_map(%__MODULE__{} = report_row) do
    report_row
    |> Map.from_struct()
    |> Map.update!(:consolidation_status, &to_string/1)
  end

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
