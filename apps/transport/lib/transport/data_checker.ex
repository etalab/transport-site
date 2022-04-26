defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.Datasets
  alias DB.{Dataset, Repo}
  import TransportWeb.Router.Helpers
  import Ecto.Query
  require Logger

  @update_data_doc_link "https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees"
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
    to_reactivate_datasets = get_to_reactivate_datasets()
    reactivated_ids = Enum.map(to_reactivate_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # Some datasets marked as active in our database may have disappeared
    # on the data gouv side, mark them as inactive.
    inactive_datasets = get_inactive_datasets()
    inactive_ids = Enum.map(inactive_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    send_inactive_dataset_mail(to_reactivate_datasets, inactive_datasets)
  end

  @doc """
  Return all the datasets locally marked as active, but active on data gouv.
  """
  def get_inactive_datasets do
    Dataset
    |> where([d], d.is_active == true)
    |> Repo.all()
    # NOTE: this method issues a HTTP call to datagouv
    |> Enum.reject(&Datasets.is_active?/1)
  end

  @doc """
  Return all the datasets locally marked as inactive, but active on data gouv.
  """
  def get_to_reactivate_datasets do
    Dataset
    |> where([d], d.is_active == false)
    |> Repo.all()
    # NOTE: this method issues a HTTP call to datagouv
    |> Enum.filter(&Datasets.is_active?/1)
  end

  def outdated_data do
    for delay <- possible_delays(),
        date = Date.add(Date.utc_today(), delay) do
      {delay, Dataset.get_expire_at(date)}
    end
    |> Enum.reject(fn {_, d} -> d == [] end)
    |> send_outdated_data_mail()
    |> Enum.map(fn x -> send_outdated_data_notifications(x) end)
  end

  def possible_delays do
    Transport.Notifications.config()
    |> Enum.filter(&(&1.reason == :expiration))
    |> Enum.flat_map(& &1.extra_delays)
    |> Enum.concat(@default_outdated_data_delays)
    |> Enum.uniq()
    |> Enum.sort()
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

          Afin qu’il puisse continuer à être utilisé par les différents acteurs, il faut qu’il soit mis à jour. Veuillez anticiper vos prochaines mises à jour. N'hésitez pas à consulter la documentation pour mettre à jour vos données #{@update_data_doc_link}.

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
    r_str =
      datasets
      |> Enum.map(&link_and_name/1)
      # credo:disable-for-next-line
      |> Enum.join("\n")

    """
    Jeux de données expirant #{delay_str(delay)}:

    #{r_str}
    """
  end

  defp delay_str(0), do: "demain"
  defp delay_str(d), do: "dans #{d} jours"

  def link(dataset) do
    base = Transport.RuntimeConfig.EmailHost.email_host()
    dataset_url(base, :details, dataset.slug)
  end

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

  defp send_outdated_data_mail(datasets = []), do: datasets

  defp send_outdated_data_mail(datasets) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données arrivant à expiration",
      make_outdated_data_body(datasets),
      ""
    )

    datasets
  end

  defp fmt_inactive_dataset([]), do: ""

  defp fmt_inactive_dataset(inactive_datasets) do
    datasets_str =
      inactive_datasets
      |> Enum.map(&link_and_name/1)
      # credo:disable-for-next-line
      |> Enum.join("\n")

    """
    Certains jeux de données ont disparus de data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_reactivated_dataset([]), do: ""

  defp fmt_reactivated_dataset(reactivated_datasets) do
    datasets_str =
      reactivated_datasets
      |> Enum.map(&link_and_name/1)
      # credo:disable-for-next-line
      |> Enum.join("\n")

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
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données qui disparaissent",
      make_inactive_dataset_body(reactivated_datasets, inactive_datasets),
      ""
    )
  end
end
