defmodule Transport.DatasetChecks do
  @moduledoc """
  Provides functions to evaluate the health and status of `DB.Dataset` resources.

  This module focuses on three primary checks:
  1. **Availability**: Identifying resources that are currently offline or unavailable.
  2. **Expiration**: Identifying resources whose validity period is nearing its end based on
     the latest validation metadata.
  3. **Validity**: Identifying resources which are not valid
  """
  use Gettext, backend: TransportWeb.Gettext
  @expire_days_ahead 7

  @type validation_list :: [DB.MultiValidation.t()]
  @type resource_with_validations :: {DB.Resource.t(), validation_list()}
  @type validation_map :: %{required(integer()) => [DB.MultiValidation.t()] | nil}
  @type check_result :: %{
          unavailable_resource: [DB.Resource.t()],
          expiring_resource: [resource_with_validations()],
          invalid_resource: [resource_with_validations()]
        }

  @spec check(DB.Dataset.t()) :: check_result()
  def check(%DB.Dataset{} = dataset) do
    dataset = DB.Repo.preload(dataset, :resources)

    validations =
      DB.MultiValidation.dataset_latest_validation(
        dataset.id,
        Transport.ValidatorsSelection.validators_for_feature(:dataset_controller)
      )

    %{
      unavailable_resource: unavailable_resource(dataset),
      expiring_resource: expiring_resource(dataset, validations),
      invalid_resource: invalid_resource(dataset, validations)
    }
  end

  def issue_name(:unavailable_resource), do: dgettext("espace-producteurs", "unavailable_resource")
  def issue_name(:expiring_resource), do: dgettext("espace-producteurs", "expiring_resource")
  def issue_name(:invalid_resource), do: dgettext("espace-producteurs", "invalid_resource")

  @spec has_issues?(check_result()) :: boolean()
  def has_issues?(result) do
    not match?(
      %{unavailable_resource: [], expiring_resource: [], invalid_resource: []},
      result
    )
  end

  @spec unavailable_resource(DB.Dataset.t()) :: [DB.Resource.t()]
  def unavailable_resource(%DB.Dataset{resources: resources}) do
    Enum.filter(resources, &(not &1.is_available))
  end

  @spec invalid_resource(DB.Dataset.t(), validation_map()) :: [resource_with_validations()]
  def invalid_resource(%DB.Dataset{} = dataset, validations) do
    dataset
    |> keep_validations(validations)
    |> Enum.filter(fn {%DB.Resource{}, [mv]} ->
      case mv do
        %DB.MultiValidation{digest: %{"max_severity" => %{"max_level" => severity}}}
        when severity in ["Error", "ERROR", "Fatal"] ->
          true

        %DB.MultiValidation{digest: %{"errors_count" => errors_count}} when errors_count > 0 ->
          true

        _ ->
          false
      end
    end)
  end

  @spec expiring_resource(DB.Dataset.t(), validation_map()) :: [resource_with_validations()]
  def expiring_resource(%DB.Dataset{} = dataset, validations) do
    dataset
    |> keep_validations(validations)
    |> Enum.filter(fn {%DB.Resource{}, [mv]} ->
      case DB.MultiValidation.get_metadata_info(mv, "end_date") do
        nil -> false
        date -> date |> Date.from_iso8601!() |> Date.diff(Date.utc_today()) <= @expire_days_ahead
      end
    end)
  end

  defp keep_validations(%DB.Dataset{} = dataset, validations) do
    dataset.resources |> Enum.map(&{&1, validations[&1.id]}) |> Enum.reject(fn {_, mv} -> is_nil(mv) end)
  end
end
