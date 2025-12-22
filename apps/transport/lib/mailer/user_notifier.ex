defmodule Transport.UserNotifier do
  @moduledoc """
  Module in charge of building emails for end users (producers, reusers, etc.)
  """
  use Phoenix.Swoosh, view: TransportWeb.EmailView, layout: {TransportWeb.LayoutView, :email}
  import Transport.AdminNotifier, only: [delay_str: 2]

  def resources_changed(%DB.Contact{} = contact, %DB.Dataset{} = dataset) do
    contact
    |> common_email_options()
    |> subject("#{dataset.custom_title} : ressources modifiées")
    |> render_body("resources_changed.html", %{dataset: dataset})
  end

  def new_comments_reuser(%DB.Contact{} = contact, datasets) do
    contact
    |> common_email_options()
    |> subject("Nouveaux commentaires sur transport.data.gouv.fr")
    |> render_body("new_comments_reuser.html", %{datasets: datasets})
  end

  def new_comments_producer(%DB.Contact{} = contact, comments_number, comments) do
    contact
    |> common_email_options()
    |> subject("#{comments_number} nouveaux commentaires sur transport.data.gouv.fr")
    |> render_body("new_comments_producer.html", comments_with_context: comments)
  end

  def promote_reuser_space(%DB.Contact{} = contact) do
    contact
    |> common_email_options()
    |> subject("Gestion de vos favoris dans votre espace réutilisateur")
    |> render_body("promote_reuser_space.html")
  end

  def dataset_now_on_nap(%DB.Contact{} = contact, dataset) do
    contact
    |> common_email_options()
    |> subject("Votre jeu de données a été référencé sur transport.data.gouv.fr")
    |> render_body("dataset_now_on_nap.html", %{
      dataset_url: TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, dataset.slug),
      dataset_custom_title: dataset.custom_title,
      contact_email_address: Application.get_env(:transport, :contact_email)
    })
  end

  def datasets_switching_climate_resilience_bill(
        %DB.Contact{} = contact,
        datasets_previously_climate_resilience,
        datasets_now_climate_resilience
      ) do
    contact
    |> common_email_options()
    |> subject("Loi climat et résilience : suivi des jeux de données")
    |> render_body("datasets_switching_climate_resilience_bill.html", %{
      datasets_now_climate_resilience: Enum.map(datasets_now_climate_resilience, &Enum.at(&1, 1)),
      datasets_previously_climate_resilience: Enum.map(datasets_previously_climate_resilience, &Enum.at(&1, 1))
    })
  end

  def multi_validation_with_error_notification(%DB.Contact{} = contact, :producer,
        dataset: dataset,
        resources: resources,
        validator_name: _,
        job_id: _
      ) do
    contact
    |> common_email_options()
    |> subject("Erreurs détectées dans le jeu de données #{dataset.custom_title}")
    |> render_body("dataset_with_error_producer.html", dataset: dataset, resources: resources)
  end

  def multi_validation_with_error_notification(%DB.Contact{} = contact, :reuser,
        dataset: dataset,
        producer_warned: producer_warned,
        validator_name: _,
        job_id: _
      ) do
    contact
    |> common_email_options()
    |> subject("Erreurs détectées dans le jeu de données #{dataset.custom_title}")
    |> render_body("dataset_with_error_reuser.html", dataset: dataset, producer_warned: producer_warned)
  end

  def resource_unavailable(%DB.Contact{} = contact, :producer,
        dataset: dataset,
        hours_consecutive_downtime: hours_consecutive_downtime,
        deleted_recreated_on_datagouv: deleted_recreated_on_datagouv,
        resource_titles: resource_titles,
        unavailabilities: _,
        job_id: _
      ) do
    contact
    |> common_email_options()
    |> subject("Ressources indisponibles dans le jeu de données #{dataset.custom_title}")
    |> render_body("resource_unavailable_producer.html",
      dataset: dataset,
      hours_consecutive_downtime: hours_consecutive_downtime,
      deleted_recreated_on_datagouv: deleted_recreated_on_datagouv,
      resource_titles: resource_titles
    )
  end

  def resource_unavailable(%DB.Contact{} = contact, :reuser,
        dataset: dataset,
        hours_consecutive_downtime: hours_consecutive_downtime,
        producer_warned: producer_warned,
        resource_titles: resource_titles,
        unavailabilities: _,
        job_id: _
      ) do
    contact
    |> common_email_options()
    |> subject("Ressources indisponibles dans le jeu de données #{dataset.custom_title}")
    |> render_body("resource_unavailable_reuser.html",
      dataset: dataset,
      hours_consecutive_downtime: hours_consecutive_downtime,
      producer_warned: producer_warned,
      resource_titles: resource_titles
    )
  end

  def periodic_reminder_producers_no_subscriptions(%DB.Contact{} = contact, datasets) do
    contact
    |> common_email_options()
    |> subject("Notifications pour vos données sur transport.data.gouv.fr")
    |> render_body("producer_without_subscriptions.html", %{datasets: datasets})
  end

  def periodic_reminder_producers_with_subscriptions(
        %DB.Contact{} = contact,
        datasets_subscribed,
        other_producers_subscribers
      ) do
    contact
    |> common_email_options()
    |> subject("Rappel : vos notifications pour vos données sur transport.data.gouv.fr")
    |> render_body("producer_with_subscriptions.html", %{
      datasets_subscribed: datasets_subscribed,
      has_other_producers_subscribers: not Enum.empty?(other_producers_subscribers),
      other_producers_subscribers: Enum.map_join(other_producers_subscribers, ", ", &DB.Contact.display_name/1)
    })
  end

  def new_datasets(%DB.Contact{} = contact, datasets) do
    contact
    |> common_email_options()
    |> subject("Nouveaux jeux de données référencés")
    |> render_body("new_dataset.html", datasets: datasets)
  end

  def expiration_producer(%DB.Contact{} = contact, dataset, resources, delay) do
    contact
    |> common_email_options()
    |> subject(expiration_email_subject(delay))
    |> render_body("expiration_producer.html",
      delay_str: delay_str(delay, :périment),
      dataset: dataset,
      resource_titles: resource_titles(resources)
    )
  end

  def expiration_reuser(%DB.Contact{} = contact, html) do
    contact
    |> common_email_options()
    |> subject("Suivi des jeux de données favoris arrivant à expiration")
    |> render_body("expiration_reuser.html", %{expiration_content: html})
  end

  def promote_producer_space(%DB.Contact{} = contact) do
    contact_email = Application.fetch_env!(:transport, :contact_email)

    contact
    |> common_email_options()
    |> subject("Bienvenue ! Découvrez votre Espace producteur")
    |> render_body("promote_producer_space.html", %{contact_email_address: contact_email})
  end

  def warn_inactivity(%DB.Contact{email: email} = contact, horizon) do
    contact
    |> common_email_options()
    |> subject("Votre compte sera supprimé #{String.downcase(horizon)}")
    |> render_body("warn_inactivity.html", contact_email: email, horizon: horizon)
  end

  # From here, utility functions.

  defp common_email_options(%DB.Contact{} = contact) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(contact)
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
end
