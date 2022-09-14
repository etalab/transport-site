defmodule Transport.Jobs.ResourceValidationJob do
  @moduledoc """
  Validate a resource and stores result in DB
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]

  @doc """
  Validate a `DB.Resource` with all validators
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) when is_integer(resource_id) do
    resource = DB.Resource |> DB.Repo.get!(resource_id)

    if DB.Resource.is_real_time?(resource) do
      resource
      |> Transport.ValidatorsSelection.validators()
      |> Enum.each(fn validator -> validator.validate_and_save(resource) end)

      :ok
    else
      {:error, "Resource##{resource_id} is not real time"}
    end
  end
end
