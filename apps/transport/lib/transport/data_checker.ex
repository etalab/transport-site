defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.Datasets
  alias DB.{Dataset, Repo}
  import TransportWeb.Router.Helpers
  import Ecto.Query
  require Logger

  @update_data_doc_link "https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees#remplacer-un-jeu-de-donnees-existant-plutot-quen-creer-un-nouveau"
  @default_outdated_data_delays [-7, -3, 0, 7, 14]

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
    inactive_datasets = for {%Dataset{is_active: true} = dataset, :inactive} <- datasets_statuses, do: dataset

    inactive_ids = Enum.map(inactive_datasets, & &1.id)

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

  def datasets_datagouv_statuses do
    Dataset |> Repo.all() |> Enum.map(&{&1, dataset_status(&1)})
  end

  @spec dataset_status(Dataset.t()) :: :active | :inactive | {:archived, DateTime.t()}
  defp dataset_status(%Dataset{datagouv_id: datagouv_id}) do
    case Datasets.get(datagouv_id) do
      {:ok, %{"archived" => nil}} ->
        :active

      {:ok, %{"archived" => archived}} ->
        # data.gouv.fr does not include the timezone
        {:ok, datetime, 0} = DateTime.from_iso8601(String.replace_suffix(archived, "Z", "") <> "Z")
        {:archived, datetime}

      {:error, _} ->
        :inactive
    end
  end

  def outdated_data do
    for delay <- possible_delays(),
        date = Date.add(Date.utc_today(), delay) do
      {delay, gtfs_datasets_expiring_on(date)}
    end
    |> Enum.reject(fn {_, d} -> d == [] end)
    |> send_outdated_data_mail()
    |> Enum.map(&send_outdated_data_notifications/1)
  end

  def gtfs_datasets_expiring_on(%Date{} = date) do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where(
      [metadata: m, resource: r],
      fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata) == ^date and r.format == "GTFS"
    )
    |> select([dataset: d], d)
    |> distinct(true)
    |> DB.Repo.all()
  end

  def possible_delays do
    Transport.Notifications.config()
    |> Enum.filter(&(&1.reason == :expiration))
    |> Enum.flat_map(& &1.extra_delays)
    |> Enum.concat(@default_outdated_data_delays)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec send_new_dataset_notifications([Dataset.t()] | []) :: no_return() | :ok
  def send_new_dataset_notifications([]), do: :ok

  def send_new_dataset_notifications(datasets) do
    dataset_link_fn = fn %Dataset{} = dataset ->
      "* #{dataset.custom_title} - (#{Dataset.type_to_str(dataset.type)}) - #{link(dataset)}"
    end

    Transport.Notifications.config()
    |> Transport.Notifications.emails_for_reason(:new_dataset)
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

        ---
        Si vous souhaitez modifier ou supprimer ces alertes, vous pouvez répondre à cet e-mail.
        """,
        ""
      )
    end)
  end

  def send_outdated_data_notifications({delay, datasets} = payload) do
    notifications_config = Transport.Notifications.config()

    datasets
    |> Enum.filter(fn dataset ->
      Enum.member?(@default_outdated_data_delays, delay) or
        Transport.Notifications.is_valid_extra_delay?(notifications_config, :expiration, dataset, delay)
    end)
    |> Enum.each(fn dataset ->
      emails = Transport.Notifications.emails_for_reason(notifications_config, :expiration, dataset)

      emails
      |> Enum.each(fn email ->
        Transport.EmailSender.impl().send_mail(
          "transport.data.gouv.fr",
          Application.get_env(:transport, :contact_email),
          email,
          Application.get_env(:transport, :contact_email),
          "Jeu de données arrivant à expiration",
          """
          Bonjour,

          Une ressource associée au jeu de données #{delay_str(delay, :expire)} :

          #{link_and_name(dataset, :datagouv_title)}

          Afin qu’il puisse continuer à être utilisé par les différents acteurs, il faut qu’il soit mis à jour. Pour cela, veuillez remplacer la ressource périmée par la nouvelle ressource : #{@update_data_doc_link}.

          Veuillez également anticiper vos prochaines mises à jour, au moins 7 jours avant l'expiration de votre fichier.

          L’équipe transport.data.gouv.fr

          ---
          Si vous souhaitez modifier ou supprimer ces alertes, vous pouvez répondre à cet e-mail.
          """,
          ""
        )
      end)
    end)

    payload
  end

  def has_expiration_notifications?(%Dataset{} = dataset) do
    Transport.Notifications.config()
    |> Transport.Notifications.emails_for_reason(:expiration, dataset)
    |> Enum.count() > 0
  end

  def expiration_notification_enabled_str(%Dataset{} = dataset) do
    if has_expiration_notifications?(dataset) do
      "✅ notification automatique"
    else
      "❌ pas de notification automatique"
    end
  end

  defp make_str({delay, datasets}) do
    dataset_str = fn %Dataset{} = dataset ->
      "#{link_and_name(dataset, :custom_title)} (#{expiration_notification_enabled_str(dataset)})"
    end

    """
    Jeux de données #{delay_str(delay, :expirant)}:

    #{Enum.map_join(datasets, "\n", &dataset_str.(&1))}
    """
  end

  @doc """
  iex> delay_str(0, :expirant)
  "expirant demain"
  iex> delay_str(0, :expire)
  "expire demain"
  iex> delay_str(2, :expirant)
  "expirant dans 2 jours"
  iex> delay_str(2, :expire)
  "expire dans 2 jours"
  iex> delay_str(-1, :expirant)
  "expirés depuis hier"
  iex> delay_str(-1, :expire)
  "expiré depuis hier"
  iex> delay_str(-2, :expirant)
  "expirés depuis 2 jours"
  iex> delay_str(-2, :expire)
  "expiré depuis 2 jours"
  """
  @spec delay_str(integer(), :expire | :expirant) :: binary()
  def delay_str(0, verb), do: "#{verb} demain"
  def delay_str(1, verb), do: "#{verb} dans 1 jour"
  def delay_str(d, verb) when d >= 2, do: "#{verb} dans #{d} jours"
  def delay_str(-1, :expirant), do: "expirés depuis hier"
  def delay_str(-1, :expire), do: "expiré depuis hier"
  def delay_str(d, :expirant) when d <= -2, do: "expirés depuis #{-d} jours"
  def delay_str(d, :expire) when d <= -2, do: "expiré depuis #{-d} jours"

  def link(%Dataset{slug: slug}), do: dataset_url(TransportWeb.Endpoint, :details, slug)

  @spec link_and_name(Dataset.t(), :datagouv_title | :custom_title) :: binary()
  def link_and_name(%Dataset{} = dataset, title_field) do
    link = link(dataset)
    name = Map.fetch!(dataset, title_field)

    " * #{name} - #{link}"
  end

  defp make_outdated_data_body(datasets) do
    """
    Bonjour,

    Voici un résumé des jeux de données arrivant à expiration

    #{Enum.map_join(datasets, "\n---------------------\n", &make_str/1)}
    """
  end

  defp send_outdated_data_mail([] = _datasets), do: []

  defp send_outdated_data_mail(datasets) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :bizdev_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données arrivant à expiration",
      make_outdated_data_body(datasets),
      ""
    )

    datasets
  end

  defp fmt_inactive_datasets([]), do: ""

  defp fmt_inactive_datasets(inactive_datasets) do
    datasets_str = Enum.map_join(inactive_datasets, "\n", &link_and_name(&1, :custom_title))

    """
    Certains jeux de données ont disparus de data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_reactivated_datasets([]), do: ""

  defp fmt_reactivated_datasets(reactivated_datasets) do
    datasets_str = Enum.map_join(reactivated_datasets, "\n", &link_and_name(&1, :custom_title))

    """
    Certains jeux de données disparus sont réapparus sur data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_archived_datasets([]), do: ""

  defp fmt_archived_datasets(archived_datasets) do
    datasets_str = Enum.map_join(archived_datasets, "\n", &link_and_name(&1, :custom_title))

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
