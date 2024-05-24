defmodule Transport.UserNotifier do
  @moduledoc """
  Module in charge of building emails for end users (producers, reusers, etc.)
  """
  use Phoenix.Swoosh, view: TransportWeb.EmailView
  import Transport.AdminNotifier, only: [delay_str: 2]

  def resources_changed(email, subject, %DB.Dataset{} = dataset) do
    email
    |> common_email_options()
    |> subject(subject)
    |> render_body("resources_changed.html", %{dataset: dataset})
  end

  def new_comments_reuser(%DB.Contact{email: email}, datasets) do
    email
    |> common_email_options()
    |> subject("Nouveaux commentaires sur transport.data.gouv.fr")
    |> render_body("new_comments_reuser.html", %{datasets: datasets})
  end

  def new_comments_producer(email, comments_number, comments) do
    email
    |> common_email_options()
    |> subject("#{comments_number} nouveaux commentaires sur transport.data.gouv.fr")
    |> render_body("new_comments_producer.html", comments_with_context: comments)
  end

  def promote_reuser_space(email) do
    email
    |> common_email_options()
    |> subject("Gestion de vos favoris dans votre espace réutilisateur")
    |> render_body("promote_reuser_space.html")
  end

  def dataset_now_on_nap(email, dataset) do
    email
    |> common_email_options()
    |> subject("Votre jeu de données a été référencé sur transport.data.gouv.fr")
    |> render_body("dataset_now_on_nap.html", %{
      dataset_url: TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, dataset.slug),
      dataset_custom_title: dataset.custom_title,
      contact_email_address: Application.get_env(:transport, :contact_email)
    })
  end

  def datasets_switching_climate_resilience_bill(
        email,
        datasets_previously_climate_resilience,
        datasets_now_climate_resilience
      ) do
    email
    |> common_email_options()
    |> subject("Loi climat et résilience : suivi des jeux de données")
    |> render_body("datasets_switching_climate_resilience_bill.html", %{
      datasets_now_climate_resilience: Enum.map(datasets_now_climate_resilience, &Enum.at(&1, 1)),
      datasets_previously_climate_resilience: Enum.map(datasets_previously_climate_resilience, &Enum.at(&1, 1))
    })
  end

  def multi_validation_with_error_notification(email, :producer, dataset: dataset, resources: resources) do
    email
    |> common_email_options()
    |> subject("Erreurs détectées dans le jeu de données #{dataset.custom_title}")
    |> render_body("dataset_with_error_producer.html", dataset: dataset, resources: resources)
  end

  def multi_validation_with_error_notification(email, :reuser, dataset: dataset, producer_warned: producer_warned) do
    email
    |> common_email_options()
    |> subject("Erreurs détectées dans le jeu de données #{dataset.custom_title}")
    |> render_body("dataset_with_error_reuser.html", dataset: dataset, producer_warned: producer_warned)
  end

  def resource_unavailable(email, :producer,
        dataset: dataset,
        hours_consecutive_downtime: hours_consecutive_downtime,
        deleted_recreated_on_datagouv: deleted_recreated_on_datagouv,
        resource_titles: resource_titles
      ) do
    email
    |> common_email_options()
    |> subject("Ressources indisponibles dans le jeu de données #{dataset.custom_title}")
    |> render_body("resource_unavailable_producer.html",
      dataset: dataset,
      hours_consecutive_downtime: hours_consecutive_downtime,
      deleted_recreated_on_datagouv: deleted_recreated_on_datagouv,
      resource_titles: resource_titles
    )
  end

  def resource_unavailable(email, :reuser,
        dataset: dataset,
        hours_consecutive_downtime: hours_consecutive_downtime,
        producer_warned: producer_warned,
        resource_titles: resource_titles
      ) do
    email
    |> common_email_options()
    |> subject("Ressources indisponibles dans le jeu de données #{dataset.custom_title}")
    |> render_body("resource_unavailable_reuser.html",
      dataset: dataset,
      hours_consecutive_downtime: hours_consecutive_downtime,
      producer_warned: producer_warned,
      resource_titles: resource_titles
    )
  end

  def periodic_reminder_producers_no_subscriptions(email, datasets) do
    email
    |> common_email_options()
    |> subject("Notifications pour vos données sur transport.data.gouv.fr")
    |> render_body("producer_without_subscriptions.html", %{datasets: datasets})
  end

  def periodic_reminder_producers_with_subscriptions(email, datasets_subscribed, other_producers_subscribers) do
    email
    |> common_email_options()
    |> subject("Rappel : vos notifications pour vos données sur transport.data.gouv.fr")
    |> render_body("producer_with_subscriptions.html", %{
      datasets_subscribed: datasets_subscribed,
      has_other_producers_subscribers: not Enum.empty?(other_producers_subscribers),
      other_producers_subscribers: Enum.map_join(other_producers_subscribers, ", ", &DB.Contact.display_name/1)
    })
  end

  def new_datasets(email, datasets) do
    dataset_link_fn = fn %DB.Dataset{} = dataset ->
      "* #{dataset.custom_title} - (#{DB.Dataset.type_to_str(dataset.type)}) - #{link(dataset)}"
    end

    text_content = """
    Bonjour,

    Les jeux de données suivants ont été référencés récemment :

    #{datasets |> Enum.sort_by(& &1.type) |> Enum.map_join("\n", &dataset_link_fn.(&1))}

    L’équipe transport.data.gouv.fr
    """

    email
    |> common_email_options()
    |> subject("Nouveaux jeux de données référencés")
    |> text_body(text_content)
  end

  def expiration_producer(email, dataset, resources, delay) do
    email
    |> common_email_options()
    |> subject(expiration_email_subject(delay))
    |> render_body("expiration_producer.html",
      delay_str: delay_str(delay, :périment),
      dataset: dataset,
      resource_titles: resource_titles(resources)
    )
  end

  def promote_producer_space(email) do
    contact_email = Application.fetch_env!(:transport, :contact_email)

    email
    |> common_email_options()
    |> subject("Bienvenue ! Découvrez votre Espace producteur")
    |> render_body("promote_producer_space.html", %{contact_email_address: contact_email})
  end

  def warn_inactivity(email, horizon) do
    email
    |> common_email_options()
    |> subject("Votre compte sera supprimé #{String.downcase(horizon)}")
    |> render_body("warn_inactivity.html", contact_email: email, horizon: horizon)
  end

  # From here, utility functions.

  defp common_email_options(email) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(email)
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
  end

  @doc """
  If all doctests are removed from here, change Transport.NotifiersTest to stop calling this module.
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
  iex> expiration_email_subject(7)
  "Jeu de données arrivant à expiration"
  iex> expiration_email_subject(0)
  "Jeu de données arrivant à expiration"
  iex> expiration_email_subject(-3)
  "Jeu de données périmé"
  """
  def expiration_email_subject(delay) when delay >= 0 do
    "Jeu de données arrivant à expiration"
  end

  def expiration_email_subject(delay) when delay < 0 do
    "Jeu de données périmé"
  end

  defp link(%DB.Dataset{slug: slug}), do: TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
end
