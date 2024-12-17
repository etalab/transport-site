defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data for toggling on and off active status of datasets depending on status on data.gouv.fr
  """
  alias DB.{Dataset, Repo}
  import Ecto.Query
  require Logger

  @type dataset_status :: :active | :inactive | :ignore | :no_producer | {:archived, DateTime.t()}

  @doc """
  This method is a scheduled job which does two things:
  - locally re-activates disabled datasets which are actually active on data gouv
  - locally disables datasets which are actually inactive on data gouv

  It also sends an email to the team via `fmt_inactive_datasets` and `fmt_reactivated_datasets`.
  """
  def inactive_data do
    # Some datasets marked as inactive in our database may have reappeared
    # on the data gouv side, we'll mark them back as active.
    datasets_statuses = datasets_datagouv_statuses()

    to_reactivate_datasets = for {%Dataset{is_active: false} = dataset, :active} <- datasets_statuses, do: dataset

    reactivated_ids = Enum.map(to_reactivate_datasets, & &1.id)

    Dataset
    |> where([d], d.id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # Some datasets marked as active in our database may have disappeared
    # on the data gouv side, mark them as inactive.
    current_nb_active_datasets = Repo.aggregate(Dataset.base_query(), :count, :id)

    inactive_datasets =
      for {%DB.Dataset{is_active: true} = dataset, status} <- datasets_statuses,
          status in [:inactive, :no_producer],
          do: dataset

    inactive_ids = Enum.map(inactive_datasets, & &1.id)
    desactivates_over_10_percent_datasets = Enum.count(inactive_datasets) > current_nb_active_datasets * 10 / 100

    if desactivates_over_10_percent_datasets do
      raise "Would desactivate over 10% of active datasets, stopping"
    end

    Dataset
    |> where([d], d.id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    # Some datasets may be archived on data.gouv.fr
    recent_limit = DateTime.add(DateTime.utc_now(), -1, :day)

    archived_datasets =
      for {%Dataset{is_active: true} = dataset, {:archived, datetime}} <- datasets_statuses,
          DateTime.compare(datetime, recent_limit) == :gt,
          do: dataset

    send_inactive_datasets_mail(to_reactivate_datasets, inactive_datasets, archived_datasets)
  end

  @spec datasets_datagouv_statuses :: [{DB.Dataset.t(), dataset_status()}]
  def datasets_datagouv_statuses do
    DB.Dataset
    |> order_by(:id)
    |> DB.Repo.all()
    |> Enum.map(&{&1, dataset_status(&1)})
  end

  @spec dataset_status(DB.Dataset.t()) :: dataset_status()
  def dataset_status(%DB.Dataset{datagouv_id: datagouv_id}) do
    case Datagouvfr.Client.Datasets.get(datagouv_id) do
      {:ok, %{"organization" => nil, "owner" => nil}} ->
        :no_producer

      {:ok, %{"archived" => nil}} ->
        :active

      {:ok, %{"archived" => archived}} ->
        {:ok, datetime, 0} = DateTime.from_iso8601(archived)
        {:archived, datetime}

      {:error, %HTTPoison.Error{} = error} ->
        log_sentry_event(datagouv_id, error)
        :ignore

      {:error, reason} when reason in [:not_found, :gone] ->
        :inactive

      {:error, error} ->
        log_sentry_event(datagouv_id, error)
        :ignore
    end
  end

  defp log_sentry_event(datagouv_id, error) do
    Sentry.capture_message(
      "Unable to get dataset status for Dataset##{datagouv_id} from data.gouv.fr",
      fingerprint: ["#{__MODULE__}:dataset_status:error"],
      extra: %{dataset_datagouv_id: datagouv_id, error_reason: inspect(error)}
    )
  end

  # Do nothing if all lists are empty
  defp send_inactive_datasets_mail([] = _reactivated_datasets, [] = _inactive_datasets, [] = _archived_datasets),
    do: nil

  defp send_inactive_datasets_mail(reactivated_datasets, inactive_datasets, archived_datasets) do
    Transport.AdminNotifier.inactive_datasets(reactivated_datasets, inactive_datasets, archived_datasets)
    |> Transport.Mailer.deliver()
  end
end
