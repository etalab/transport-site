defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.{Datasets, Discussions}
  alias DB.{Dataset, Repo}
  import TransportWeb.Router.Helpers
  import Ecto.Query
  require Logger

  @update_data_doc_link "https://doc.transport.data.gouv.fr/producteurs/mettre-a-jour-des-donnees"
  @default_outdated_data_delays [0, 7, 14]

  def inactive_data do
    # we first check if some inactive datasets have reapeared
    to_reactivate_datasets = get_to_reactivate_datasets()
    reactivated_ids = Enum.map(to_reactivate_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # then we disable the unreachable datasets
    inactive_datasets = get_inactive_datasets()
    inactive_ids = Enum.map(inactive_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    send_inactive_dataset_mail(to_reactivate_datasets, inactive_datasets)
  end

  def get_inactive_datasets do
    Dataset
    |> where([d], d.is_active == true)
    |> Repo.all()
    |> Enum.reject(&Datasets.is_active?/1)
  end

  def get_to_reactivate_datasets do
    Dataset
    |> where([d], d.is_active == false)
    |> Repo.all()
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

    # |> post_outdated_data_comments(blank)
  end

  def post_outdated_data_comments(delays_datasets) do
    case Enum.find(delays_datasets, fn {delay, _} -> delay == 7 end) do
      nil ->
        Logger.info("No datasets need a comment about outdated resources")

      {delay, datasets} ->
        Enum.map(datasets, fn r -> post_outdated_data_comment(r, delay) end)
    end
  end

  def post_outdated_data_comment(dataset, delay) do
    # TODO: verify how to mock this & verify assertions
    Discussions.post(
      dataset.datagouv_id,
      "Jeu de données arrivant à expiration",
      """
      Bonjour,
      Ce jeu de données arrive à expiration dans #{delay} jour#{if delay != 1 do
        "s"
      end}.
      Afin qu’il puisse continuer à être utilisé par les différents acteurs, il faut qu’il soit mis à jour prochainement.
      L’équipe transport.data.gouv.fr
      """
    )
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

  defp send_outdated_data_mail([], _), do: []

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

  defp send_inactive_dataset_mail([], []), do: nil

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
