defmodule Transport.DatasetChecks do
  @moduledoc """
  Provides functions to evaluate the health and status of `DB.Dataset` resources.

  This module focuses on the following checks:
  1. **Availability**: Identifying resources that are currently offline or unavailable.
  2. **Expiration**: Identifying resources whose validity period is nearing its end based on
     the latest validation metadata.
  3. **Validity**: Identifying resources which are not valid
  4. **Unanswered discussion**: Identifying discussions that have not been answered in the
     the last 30 days.
  """
  use Gettext, backend: TransportWeb.Gettext

  @expire_days_ahead 7
  @unanswered_discussion_since_days 30
  @recent_discussions_days 7

  @gtfs_rt_validator Transport.Validators.GTFSRT.validator_name()
  @gtfs_rt_errors_threshold 50

  @type validation_list :: [DB.MultiValidation.t()]
  @type resource_with_validations :: {DB.Resource.t(), validation_list()}
  @type validation_map :: %{required(integer()) => [DB.MultiValidation.t()] | nil}
  @type check_result_producer :: %{
          unavailable_resource: [DB.Resource.t()],
          expiring_resource: [resource_with_validations()],
          invalid_resource: [resource_with_validations()],
          unanswered_discussions: [map()]
        }

  @type check_result_reuser :: %{
          unavailable_resource: [DB.Resource.t()],
          expiring_resource: [resource_with_validations()],
          invalid_resource: [resource_with_validations()],
          recent_discussions: [map()]
        }
  @spec check(DB.Dataset.t(), :producer | :reuser) :: check_result_producer() | check_result_reuser()
  def check(%DB.Dataset{} = dataset, mode) do
    dataset = DB.Repo.preload(dataset, :resources)

    validations =
      DB.MultiValidation.dataset_latest_validation(
        dataset.id,
        Transport.ValidatorsSelection.validators_for_feature(:dataset_checks),
        include_result: true
      )

    case mode do
      :producer ->
        %{
          unavailable_resource: unavailable_resource(dataset),
          expiring_resource: expiring_resource(dataset, validations),
          invalid_resource: invalid_resource(dataset, validations),
          unanswered_discussions: unanswered_discussions(dataset)
        }

      :reuser ->
        %{
          unavailable_resource: unavailable_resource(dataset),
          expiring_resource: expiring_resource(dataset, validations),
          invalid_resource: invalid_resource(dataset, validations),
          recent_discussions: recent_discussions(dataset)
        }
    end
  end

  def issue_name(:unavailable_resource), do: dgettext("espace-producteurs", "unavailable_resource")
  def issue_name(:expiring_resource), do: dgettext("espace-producteurs", "expiring_resource")
  def issue_name(:invalid_resource), do: dgettext("espace-producteurs", "invalid_resource")
  def issue_name(:unanswered_discussions), do: dgettext("espace-producteurs", "unanswered_discussions")
  def issue_name(:recent_discussions), do: dgettext("espace-producteurs", "recent_discussions")

  @spec has_issues?(check_result_producer() | check_result_reuser()) :: boolean()
  def has_issues?(result), do: count_issues(result) >= 1

  @spec count_issues(check_result_producer() | check_result_reuser()) :: non_neg_integer()
  def count_issues(result) do
    result |> Map.values() |> Enum.flat_map(fn x -> x end) |> Enum.count()
  end

  @spec unavailable_resource(DB.Dataset.t()) :: [DB.Resource.t()]
  def unavailable_resource(%DB.Dataset{resources: resources}) do
    Enum.filter(resources, &(not &1.is_available))
  end

  @spec invalid_resource(DB.Dataset.t(), validation_map()) :: [resource_with_validations()]
  def invalid_resource(%DB.Dataset{} = dataset, validations) do
    dataset
    |> keep_validations(validations)
    |> Enum.filter(fn {%DB.Resource{}, [mv | _]} ->
      case mv do
        %DB.MultiValidation{validator: @gtfs_rt_validator, result: %{"errors" => errors}} ->
          # See https://github.com/MobilityData/gtfs-realtime-validator/blob/master/RULES.md
          high_severity_errors = ["E003", "E004", "E011", "E034"]

          errors
          |> Enum.filter(&(&1["error_id"] in high_severity_errors))
          |> Enum.sum_by(& &1["errors_count"]) >= @gtfs_rt_errors_threshold

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
    |> Enum.filter(fn {%DB.Resource{}, [mv | _]} ->
      case DB.MultiValidation.get_metadata_info(mv, "end_date") do
        nil -> false
        date -> date |> Date.from_iso8601!() |> Date.diff(Date.utc_today()) <= @expire_days_ahead
      end
    end)
  end

  @spec unanswered_discussions(DB.Dataset.t()) :: [map()]
  def unanswered_discussions(%DB.Dataset{} = dataset) do
    team_member_ids = team_member_ids(dataset)

    Datagouvfr.Client.Discussions.Wrapper.get(dataset.datagouv_id)
    |> Enum.reject(&closed_discussion?/1)
    |> Enum.filter(fn discussion -> discussion_since(discussion, @unanswered_discussion_since_days) end)
    |> Enum.reject(&answered_by_team_member(&1, team_member_ids))
  end

  @spec recent_discussions(DB.Dataset.t()) :: [map()]
  def recent_discussions(%DB.Dataset{} = dataset) do
    Datagouvfr.Client.Discussions.Wrapper.get(dataset.datagouv_id)
    |> Enum.filter(fn discussion -> discussion_since(discussion, @recent_discussions_days) end)
  end

  def closed_discussion?(%{"closed" => closed}), do: not is_nil(closed)

  def discussion_since(%{"discussion" => comment_list}, since_days) do
    latest_comment_datetime =
      comment_list
      |> Enum.map(fn comment ->
        {:ok, comment_datetime, 0} = DateTime.from_iso8601(comment["posted_on"])
        comment_datetime
      end)
      |> Enum.max(DateTime)

    month_ago = DateTime.utc_now() |> DateTime.add(-since_days, :day)
    Date.after?(latest_comment_datetime, month_ago)
  end

  def answered_by_team_member(%{"discussion" => comment_list}, team_member_ids) do
    %{"posted_by" => %{"id" => author_id}} = comment_list |> List.last()
    author_id in team_member_ids
  end

  defp team_member_ids(%DB.Dataset{organization_id: organization_id}) do
    case Datagouvfr.Client.Organization.Wrapper.get(organization_id, restrict_fields: true) do
      {:ok, %{"members" => members}} ->
        Enum.map(members, fn member -> member["user"]["id"] end)

      _ ->
        []
    end
  end

  defp keep_validations(%DB.Dataset{} = dataset, validations) do
    dataset.resources |> Enum.map(&{&1, validations[&1.id]}) |> Enum.reject(fn {_, mv} -> is_nil(mv) end)
  end
end
