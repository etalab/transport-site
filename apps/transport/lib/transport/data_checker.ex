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
  @default_outdated_data_delays [0, 7, 14]

  @doc """
  This method is a scheduled job which does two things:
  - locally re-activates disabled datasets which are actually active on data gouv
  - locally disables datasets which are actually inactive on data gouv

  It also sends an email to the team via `fmt_inactive_dataset` and `fmt_reactivated_dataset`.
  """
  def inactive_data do
    # Some datasets marked as inactive in our database may have reappeared
    # on the data gouv side, we'll mark them back as active.
    datasets_statuses = datasets_datagouv_statuses()

    to_reactivate_datasets =
      datasets_statuses
      |> Enum.filter(fn {%Dataset{is_active: is_active}, status} -> not is_active and status == :active end)
      |> Enum.map(fn {%Dataset{} = dataset, _status} -> dataset end)

    reactivated_ids = Enum.map(to_reactivate_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # Some datasets marked as active in our database may have disappeared
    # on the data gouv side, mark them as inactive.
    inactive_datasets =
      datasets_statuses
      |> Enum.filter(fn {%Dataset{is_active: is_active}, status} -> is_active and status == :inactive end)
      |> Enum.map(fn {%Dataset{} = dataset, _status} -> dataset end)

    inactive_ids = Enum.map(inactive_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    send_inactive_dataset_mail(to_reactivate_datasets, inactive_datasets)
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
    |> Enum.map(fn x -> send_outdated_data_notifications(x) end)
  end

  def gtfs_datasets_expiring_on(%Date{} = date) do
    Transport.Validators.GTFSTransport.validator_name()
    |> DB.Dataset.join_from_dataset_to_metadata()
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

          Une ressource associée au jeu de données expire #{delay_str(delay)} :

          #{link_and_name(dataset)}

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

  defp make_str({delay, datasets}) do
    r_str = datasets |> Enum.map_join("\n", &link_and_name/1)

    """
    Jeux de données expirant #{delay_str(delay)}:

    #{r_str}
    """
  end

  defp delay_str(0), do: "demain"
  defp delay_str(d), do: "dans #{d} jours"

  def link(%Dataset{slug: slug}), do: dataset_url(TransportWeb.Endpoint, :details, slug)

  def link_and_name(dataset) do
    link = link(dataset)
    name = dataset.datagouv_title

    " * #{name} - #{link}"
  end

  defp make_outdated_data_body(datasets) do
    # credo:disable-for-lines:5
    """
    Bonjour,
    Voici un résumé des jeux de données arrivant à expiration

    #{datasets |> Enum.map(&make_str/1) |> Enum.join("\n---------------------\n")}

    À vous de jouer !
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

  defp fmt_inactive_dataset([]), do: ""

  defp fmt_inactive_dataset(inactive_datasets) do
    datasets_str = inactive_datasets |> Enum.map_join("\n", &link_and_name/1)

    """
    Certains jeux de données ont disparus de data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_reactivated_dataset([]), do: ""

  defp fmt_reactivated_dataset(reactivated_datasets) do
    datasets_str = reactivated_datasets |> Enum.map_join("\n", &link_and_name/1)

    """
    Certains jeux de données disparus sont réapparus sur data.gouv.fr :
    #{datasets_str}
    """
  end

  defp make_inactive_dataset_body(reactivated_datasets, inactive_datasets) do
    reactivated_datasets_str = fmt_reactivated_dataset(reactivated_datasets)
    inactive_datasets_str = fmt_inactive_dataset(inactive_datasets)

    """
    Bonjour,
    #{inactive_datasets_str}
    #{reactivated_datasets_str}

    Il faut peut être creuser pour savoir si c'est normal.
    """
  end

  # Do nothing if both lists are empty
  defp send_inactive_dataset_mail([] = _reactivated_datasets, [] = _inactive_datasets), do: nil

  defp send_inactive_dataset_mail(reactivated_datasets, inactive_datasets) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :bizdev_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données qui disparaissent",
      make_inactive_dataset_body(reactivated_datasets, inactive_datasets),
      ""
    )
  end
end
