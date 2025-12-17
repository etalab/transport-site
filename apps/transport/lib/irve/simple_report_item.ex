defmodule Transport.IRVE.SimpleReportItem do
  @moduledoc """
  Quick & dirty structure to massage the outcome into a report with all the same keys
  (as expected by the `DataFrame` that we use to create the CSV file).

  It's all quite tied to the other module here.
  """
  @enforce_keys [:dataset_id, :resource_id, :url, :dataset_title, :status]
  defstruct [:dataset_id, :resource_id, :url, :dataset_title, :status, :error_message, :error_type]

  def from_result({:error_occurred, error, resource}) do
    new(resource, :error_occurred, error)
  end

  def from_result({status, resource}) do
    new(resource, status, nil)
  end

  def to_map(%__MODULE__{} = report_row) do
    report_row
    |> Map.from_struct()
    |> Map.update!(:status, &to_string/1)
  end

  defp new(resource, status, error) do
    %__MODULE__{
      dataset_id: resource.dataset_id,
      resource_id: resource.resource_id,
      url: resource.url,
      dataset_title: resource.dataset_title,
      status: status,
      error_message: maybe_error_message(error),
      error_type: maybe_error_type(error)
    }
  end

  defp maybe_error_message(nil), do: nil
  defp maybe_error_message(error), do: Exception.message(error)

  defp maybe_error_type(nil), do: nil
  defp maybe_error_type(error), do: error.__struct__ |> inspect()
end
