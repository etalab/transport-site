defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.Datasets
  alias Mailjet.Client
  alias Transport.{Dataset, Repo, Resource}
  import TransportWeb.Router.Helpers
  import Ecto.Query

  def inactive_data do
    # we first check if some inactive datasets have reapeared
    reactivated_datasets =
    Dataset
      |> where([d], d.is_active == false)
      |> Repo.all()
      |> Enum.filter(&Datasets.is_active?/1)

    reactivated_ids = reactivated_datasets |> Enum.map(& &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # then we disable the unreachable datasets
    inactive_datasets =
    Dataset
    |> where([d], d.is_active == true)
    |> Repo.all()
    |> Enum.reject(&Datasets.is_active?/1)
    inactive_ids = inactive_datasets |> Enum.map(& &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    send_inactive_dataset_mail(reactivated_datasets, inactive_datasets)
  end

  def outdated_data(blank \\ False) do
    for delay <- [0, 7, 14],
        date = Date.add(Date.utc_today, delay) do
          {delay, Resource.get_expire_at(date)}
        end
    |> Enum.reject(fn {_, d} -> d == [] end)
    |> send_outdated_data_mail(blank)
  end

  defp make_str({delay, resources}) do
    r_str = resources
    |> Enum.map(& &1.dataset)
    |> Enum.map(&link_and_name/1)
    |> Enum.join("\n")

    """
    Jeux de données expirant #{delay_str(delay)}:

    #{r_str}
    """
  end

  defp delay_str(0), do: "demain"
  defp delay_str(d), do: "dans #{d} jours"

  defp link_and_name(dataset) do
    link = dataset_url(TransportWeb.Endpoint, :details, dataset.slug)
    name = dataset.title

    " * #{name} - #{link}"
  end

  defp make_outdated_data_body(datasets) do
    """
    Bonjour,
    Voici un résumé des jeux de données arrivant à expiration

    #{datasets |> Enum.map(&make_str/1) |> Enum.join("\n---------------------\n")}

    À vous de jouer !
    """
  end

  defp send_outdated_data_mail([], _), do: []
  defp send_outdated_data_mail(datasets, is_blank) do
    Client.send_mail(
      "transport.data.gouv.fr",
      "contact@transport.beta.gouv.fr",
      "contact@transport.beta.gouv.fr",
      "Jeux de données arrivant à expiration",
      make_outdated_data_body(datasets),
      is_blank
    )

    datasets
  end

  defp fmt_inactive_dataset([]), do: ""
  defp fmt_inactive_dataset(inactive_datasets) do
    datasets_str = inactive_datasets
    |> Enum.map(&link_and_name/1)
    |> Enum.join("\n")
    """
    Certains jeux de données ont disparus de data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_reactivated_dataset([]), do: ""
  defp fmt_reactivated_dataset(reactivated_datasets) do
    datasets_str = reactivated_datasets
    |> Enum.map(&link_and_name/1)
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
    Client.send_mail(
      "transport.data.gouv.fr",
      "contact@transport.beta.gouv.fr",
      "contact@transport.beta.gouv.fr",
      "Jeux de données qui disparaissent",
      make_inactive_dataset_body(reactivated_datasets, inactive_datasets)
    )
  end

end
