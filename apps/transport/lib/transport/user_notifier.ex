defmodule Transport.UserNotifier do
  use Phoenix.Swoosh, view: TransportWeb.EmailView

  @moduledoc """
  Module in charge of building emails.
  First all admin emails, then all user emails.
  """

  def contact(email, subject, question) do
    new()
    |> from({"PAN, Formulaire Contact", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(email)
    |> subject(subject)
    |> text_body(question)
  end

  def feedback(rating, explanation, email, feature) do
    rating_t = %{like: "j’aime", neutral: "neutre", dislike: "mécontent"}

    reply_email = if email, do: email, else: Application.fetch_env!(:transport, :contact_email)

    feedback_content = """
    Vous avez un nouvel avis sur le PAN.
    Fonctionnalité : #{feature}
    Notation : #{rating_t[rating]}
    Adresse e-mail : #{email}

    Explication : #{explanation}
    """

    new()
    |> from({"Formulaire feedback", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(reply_email)
    |> subject("Nouvel avis pour #{feature} : #{rating_t[rating]}")
    |> text_body(feedback_content)
  end

  def bnlc_consolidation_report(subject, body, file_url) do
    report_content = """
    #{body}
    <br/><br/>
    🔗 <a href="#{file_url}">Fichier consolidé</a>
    """

    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.get_env(:transport, :bizdev_email))
    |> subject(subject)
    |> html_body(report_content)
  end

  def datasets_without_gtfs_rt_related_resources(datasets) do
    links =
      Enum.map_join(datasets, "\n", fn %DB.Dataset{slug: slug, custom_title: custom_title} ->
        link = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
        "* #{custom_title} - #{link}"
      end)

    text_body = """
    Bonjour,

    Les jeux de données suivants contiennent plusieurs GTFS et des liens entre les ressources GTFS-RT et GTFS sont manquants :

    #{links}

    L’équipe transport.data.gouv.fr

    """

    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject("Jeux de données GTFS-RT sans ressources liées")
    |> text_body(text_body)
  end

  def datasets_climate_resilience_bill_inappropriate_licence(datasets) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :bizdev_email))
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject("Jeux de données article 122 avec licence inappropriée")
    |> render_body("datasets_climate_resilience_bill_inappropriate_licence.html", %{datasets: datasets})
  end

  def new_datagouv_datasets(datasets, duration) do
    text_body = """
    Bonjour,

    Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières #{duration}h et sont susceptibles d'avoir leur place sur le PAN :

    #{Enum.map_join(datasets, "\n", &link_and_name/1)}

    ---
    Vous pouvez consulter et modifier les règles de cette tâche : https://github.com/etalab/transport-site/blob/master/apps/transport/lib/jobs/new_datagouv_datasets_job.ex
    """

    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :bizdev_email))
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject("Nouveaux jeux de données à référencer - data.gouv.fr")
    |> text_body(text_body)
  end

  # Starting from here, all the functions are used to send emails to users

  def resources_changed(email, subject, %DB.Dataset{} = dataset) do
    email
    |> common_email_options()
    |> subject(subject)
    |> render_body("resources_changed.html", %{dataset: dataset})
  end

  def new_comments(%DB.Contact{email: email}, datasets) do
    email
    |> common_email_options()
    |> subject("Nouveaux commentaires")
    |> render_body("new_comments_reuser.html", %{datasets: datasets})
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

  defp common_email_options(email) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(email)
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
  end

  defp link_and_name(%{"title" => title, "page" => page}) do
    ~s(* #{title} - #{page})
  end
end
