defmodule Transport.Jobs.NeTExGenericConverter do
  @moduledoc """
  Provides some functions to convert NeTEx to another format.
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
    GenericConverter.enqueue_all_conversion_jobs("NeTEx", format, conversion_job_module)
  end

  @doc """
  Converts a resource_history to the targeted format, using a converter module
  """
  @spec perform_single_conversion_job(integer(), binary(), module()) :: :ok
  def perform_single_conversion_job(resource_history_id, format, converter_module) do
    GenericConverter.perform_single_conversion_job(resource_history_id, :NeTEx, format, converter_module)
  end
end
