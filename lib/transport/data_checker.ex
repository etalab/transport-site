defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Mailjet.Client
  alias Transport.Resource
  import TransportWeb.Router.Helpers

  def outdated_data(blank \\ False) do
    today = Date.utc_today

    for delay <- [0, 7, 14],
        date = Date.add(today, delay) do
          make_str(date)
        end
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n---------------------\n")
    |> send_mail(blank)
  end

  defp make_str(%Date{} = date), do: date |> Resource.get_expire_at() |> make_str(date)
  defp make_str([], _date), do: nil
  defp make_str(resources, date) do
    r_str = resources
    |> Enum.map(&link_and_name/1)
    |> Enum.join("\n")

    """
    Jeux de données expirant le #{date}:

    #{r_str}
    """
  end

  defp link_and_name(resource) do
    link = dataset_url(TransportWeb.Endpoint, :details, resource.dataset.slug)
    name = resource.dataset.title

    " * #{name} - #{link}"
  end

  defp make_body(datasets) do
    """
    Bonjour,
    Voici un résumé des jeux de données arrivant à expiration

    #{datasets}

    À vous de jouer !
    """
  end

  defp send_mail("", _), do: nil
  defp send_mail(datasets, False) do
    Client.send_mail(
      "transport.data.gouv.fr",
      "contact@transport.beta.gouv.fr",
      "contact@transport.beta.gouv.fr",
      "Jeux de données arrivant à expiration",
      make_body(datasets)
    )
  end
  defp send_mail(datasets, True), do: make_body(datasets)
end
