defmodule Transport.Jobs.GTFSGenericConverter do
  @moduledoc """
  Provides some functions to convert GTFS to another format.

  Note that the EnRoute's GTFS to NeTEx converter does not use this class
  because the conversion is not done locally but through an API.
  """
  alias Transport.Jobs.GenericConverter

  @doc """
  Enqueues conversion jobs for all resource history that need one.
  """
  @spec enqueue_all_conversion_jobs(binary(), module() | [module()]) :: :ok
  def enqueue_all_conversion_jobs(format, conversion_job_modules)
      when is_list(conversion_job_modules) do
    Enum.each(conversion_job_modules, &enqueue_all_conversion_jobs(format, &1))
  end

  def enqueue_all_conversion_jobs(format, conversion_job_module) do
    GenericConverter.enqueue_all_conversion_jobs("GTFS", format, conversion_job_module)
  end

  @doc """
  Converts a resource_history to the targeted format, using a converter module
  """
  @spec perform_single_conversion_job(integer(), binary(), module()) :: :ok
  def perform_single_conversion_job(resource_history_id, format, converter_module) do
    GenericConverter.perform_single_conversion_job(resource_history_id, :GTFS, format, converter_module)
  end
end
