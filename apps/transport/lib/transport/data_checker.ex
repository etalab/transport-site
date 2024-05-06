defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.Datasets
  alias DB.{Dataset, Repo}
  import TransportWeb.Router.Helpers
  import Ecto.Query
  require Logger

  @type delay_and_records :: {integer(), [{DB.Dataset.t(), [DB.Resource.t()]}]}
  @expiration_reason DB.NotificationSubscription.reason(:expiration)
  @new_dataset_reason DB.NotificationSubscription.reason(:new_dataset)
  # If delay < 0, the resource is already expired
  @default_outdated_data_delays [-90, -60, -30, -45, -15, -7, -3, 0, 7, 14]

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
    inactive_datasets = for {%Dataset{is_active: true} = dataset, :inactive} <- datasets_statuses, do: dataset

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

  @spec datasets_datagouv_statuses :: list
  def datasets_datagouv_statuses do
    Dataset
    |> order_by(:id)
    |> Repo.all()
    |> Enum.map(&{&1, dataset_status(&1)})
  end

  @spec dataset_status(Dataset.t()) :: :active | :inactive | :ignore | {:archived, DateTime.t()}
  defp dataset_status(%Dataset{datagouv_id: datagouv_id}) do
    case Datasets.get(datagouv_id) do
      {:ok, %{"archived" => nil}} ->
        :active

      {:ok, %{"archived" => archived}} ->
        {:ok, datetime, 0} = DateTime.from_iso8601(archived)
        {:archived, datetime}

      {:error, %HTTPoison.Error{} = error} ->
        Sentry.capture_message(
          "Unable to get Dataset status from data.gouv.fr",
          extra: %{dataset_datagouv_id: datagouv_id, error_reason: inspect(error)}
        )

        :ignore

      {:error, reason} when reason in [:not_found, :gone] ->
        :inactive

      {:error, error} ->
        Sentry.capture_message(
          "Unable to get Dataset status from data.gouv.fr",
          extra: %{dataset_datagouv_id: datagouv_id, error_reason: inspect(error)}
        )

        :ignore
    end
  end

  def outdated_data do
    for delay <- possible_delays(),
        date = Date.add(Date.utc_today(), delay) do
      {delay, gtfs_datasets_expiring_on(date)}
    end
    |> Enum.reject(fn {_, records} -> Enum.empty?(records) end)
    |> send_outdated_data_mail()
    |> Enum.map(&send_outdated_data_notifications/1)
  end

  @spec gtfs_datasets_expiring_on(Date.t()) :: [{DB.Dataset.t(), [DB.Resource.t()]}]
  def gtfs_datasets_expiring_on(%Date{} = date) do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where(
      [metadata: m, resource: r],
      fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) == ^date and r.format == "GTFS"
    )
    |> select([dataset: d, resource: r], {d, r})
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.group_by(fn {%DB.Dataset{} = d, _} -> d end, fn {_, %DB.Resource{} = r} -> r end)
    |> Enum.to_list()
  end

  def possible_delays do
    @default_outdated_data_delays
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec send_new_dataset_notifications([Dataset.t()] | []) :: no_return() | :ok
  def send_new_dataset_notifications([]), do: :ok

  def send_new_dataset_notifications(datasets) do
    dataset_link_fn = fn %Dataset{} = dataset ->
      "* #{dataset.custom_title} - (#{Dataset.type_to_str(dataset.type)}) - #{link(dataset)}"
    end

    @new_dataset_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_and_role(:reuser)
    |> DB.NotificationSubscription.subscriptions_to_emails()
    |> Enum.each(fn email ->
      Transport.EmailSender.impl().send_mail(
        "transport.data.gouv.fr",
        Application.get_env(:transport, :contact_email),
        email,
        Application.get_env(:transport, :contact_email),
        "Nouveaux jeux de données référencés",
        """
        Bonjour,

        Les jeux de données suivants ont été référencés récemment :

        #{datasets |> Enum.sort_by(& &1.type) |> Enum.map_join("\n", &dataset_link_fn.(&1))}

        L’équipe transport.data.gouv.fr
        """,
        ""
      )

      datasets
      |> Enum.each(fn %Dataset{} = dataset ->
        save_notification(:new_dataset, dataset, email)
      end)
    end)
  end

  @spec send_outdated_data_notifications(delay_and_records()) :: delay_and_records()
  def send_outdated_data_notifications({delay, records} = payload) do
    Enum.each(records, fn {%DB.Dataset{} = dataset, resources} ->
      emails =
        @expiration_reason
        |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, :producer)
        |> DB.NotificationSubscription.subscriptions_to_emails()

      Enum.each(emails, fn email ->
        Transport.EmailSender.impl().send_mail(
          "transport.data.gouv.fr",
          Application.get_env(:transport, :contact_email),
          email,
          Application.get_env(:transport, :contact_email),
          email_subject(delay),
          "",
          Phoenix.View.render_to_string(TransportWeb.EmailView, "expiration_producer.html",
            delay_str: delay_str(delay, :périment),
            dataset: dataset,
            resource_titles: resource_titles(resources)
          )
        )

        save_notification(@expiration_reason, dataset, email)
      end)
    end)

    payload
  end

  @doc """
  iex> resource_titles([%DB.Resource{title: "B"}])
  "B"
  iex> resource_titles([%DB.Resource{title: "B"}, %DB.Resource{title: "A"}])
  "A, B"
  """
  def resource_titles(resources) do
    resources
    |> Enum.sort_by(fn %DB.Resource{title: title} -> title end)
    |> Enum.map_join(", ", fn %DB.Resource{title: title} -> title end)
  end

  @doc """
  iex> email_subject(7)
  "Jeu de données arrivant à expiration"
  iex> email_subject(0)
  "Jeu de données arrivant à expiration"
  iex> email_subject(-3)
  "Jeu de données périmé"
  """
  def email_subject(delay) when delay >= 0 do
    "Jeu de données arrivant à expiration"
  end

  def email_subject(delay) when delay < 0 do
    "Jeu de données périmé"
  end

  defp save_notification(reason, %Dataset{} = dataset, email) do
    DB.Notification.insert!(reason, dataset, email)
  end

  def has_expiration_notifications?(%Dataset{} = dataset) do
    @expiration_reason
    |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, :producer)
    |> Enum.count() > 0
  end

  def expiration_notification_enabled_str(%Dataset{} = dataset) do
    if has_expiration_notifications?(dataset) do
      "✅ notification automatique"
    else
      "❌ pas de notification automatique"
    end
  end

  defp climate_resilience_str(%Dataset{} = dataset) do
    if DB.Dataset.climate_resilience_bill?(dataset) do
      "⚖️🗺️ article 122"
    else
      ""
    end
  end

  @spec make_str(delay_and_records()) :: binary()
  defp make_str({delay, records}) do
    datasets = Enum.map(records, fn {%DB.Dataset{} = d, _} -> d end)

    dataset_str = fn %Dataset{} = dataset ->
      "#{link_and_name(dataset)} (#{expiration_notification_enabled_str(dataset)}) #{climate_resilience_str(dataset)}"
      |> String.trim()
    end

    """
    Jeux de données #{delay_str(delay, :périmant)} :

    #{Enum.map_join(datasets, "\n", &dataset_str.(&1))}
    """
  end

  @doc """
  iex> delay_str(0, :périmant)
  "périmant demain"
  iex> delay_str(0, :périment)
  "périment demain"
  iex> delay_str(2, :périmant)
  "périmant dans 2 jours"
  iex> delay_str(2, :périment)
  "périment dans 2 jours"
  iex> delay_str(-1, :périmant)
  "périmé depuis hier"
  iex> delay_str(-1, :périment)
  "sont périmées depuis hier"
  iex> delay_str(-2, :périmant)
  "périmés depuis 2 jours"
  iex> delay_str(-2, :périment)
  "sont périmées depuis 2 jours"
  iex> delay_str(-60, :périment)
  "sont périmées depuis 60 jours"
  """
  @spec delay_str(integer(), :périment | :périmant) :: binary()
  def delay_str(0, verb), do: "#{verb} demain"
  def delay_str(1, verb), do: "#{verb} dans 1 jour"
  def delay_str(d, verb) when d >= 2, do: "#{verb} dans #{d} jours"
  def delay_str(-1, :périmant), do: "périmé depuis hier"
  def delay_str(-1, :périment), do: "sont périmées depuis hier"
  def delay_str(d, :périmant) when d <= -2, do: "périmés depuis #{-d} jours"
  def delay_str(d, :périment) when d <= -2, do: "sont périmées depuis #{-d} jours"

  def link(%Dataset{slug: slug}), do: dataset_url(TransportWeb.Endpoint, :details, slug)

  @spec link_and_name(Dataset.t()) :: binary()
  def link_and_name(%Dataset{custom_title: custom_title} = dataset) do
    link = link(dataset)

    " * #{custom_title} - #{link}"
  end

  defp make_outdated_data_body(records) do
    """
    Bonjour,

    Voici un résumé des jeux de données arrivant à expiration

    #{Enum.map_join(records, "\n---------------------\n", &make_str/1)}
    """
  end

  @spec send_outdated_data_mail([delay_and_records()]) :: [delay_and_records()]
  defp send_outdated_data_mail([] = _records), do: []

  defp send_outdated_data_mail(records) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :bizdev_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données arrivant à expiration",
      make_outdated_data_body(records),
      ""
    )

    records
  end

  defp fmt_inactive_datasets([]), do: ""

  defp fmt_inactive_datasets(inactive_datasets) do
    datasets_str = Enum.map_join(inactive_datasets, "\n", &link_and_name(&1))

    """
    Certains jeux de données ont disparus de data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_reactivated_datasets([]), do: ""

  defp fmt_reactivated_datasets(reactivated_datasets) do
    datasets_str = Enum.map_join(reactivated_datasets, "\n", &link_and_name(&1))

    """
    Certains jeux de données disparus sont réapparus sur data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_archived_datasets([]), do: ""

  defp fmt_archived_datasets(archived_datasets) do
    datasets_str = Enum.map_join(archived_datasets, "\n", &link_and_name(&1))

    """
    Certains jeux de données sont indiqués comme archivés sur data.gouv.fr :
    #{datasets_str}

    #{count_archived_datasets()} jeux de données sont archivés. Retrouvez-les dans le backoffice : #{backoffice_archived_datasets_url()}
    """
  end

  defp backoffice_archived_datasets_url do
    backoffice_page_url(TransportWeb.Endpoint, :index, %{"filter" => "archived"}) <> "#list_datasets"
  end

  def count_archived_datasets do
    Dataset.archived() |> Repo.aggregate(:count, :id)
  end

  defp make_inactive_datasets_body(reactivated_datasets, inactive_datasets, archived_datasets) do
    reactivated_datasets_str = fmt_reactivated_datasets(reactivated_datasets)
    inactive_datasets_str = fmt_inactive_datasets(inactive_datasets)
    archived_datasets_str = fmt_archived_datasets(archived_datasets)

    """
    Bonjour,
    #{inactive_datasets_str}
    #{reactivated_datasets_str}
    #{archived_datasets_str}

    Il faut peut être creuser pour savoir si c'est normal.
    """
  end

  # Do nothing if all lists are empty
  defp send_inactive_datasets_mail([] = _reactivated_datasets, [] = _inactive_datasets, [] = _archived_datasets),
    do: nil

  defp send_inactive_datasets_mail(reactivated_datasets, inactive_datasets, archived_datasets) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :bizdev_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données supprimés ou archivés",
      make_inactive_datasets_body(reactivated_datasets, inactive_datasets, archived_datasets),
      ""
    )
  end
end
