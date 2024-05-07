defmodule Transport.UserNotifier do
  use Phoenix.Swoosh, view: TransportWeb.EmailView

  @moduledoc """
  Module in charge of building emails.
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

  def resources_changed(email, subject, %DB.Dataset{} = dataset) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(email)
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject(subject)
    |> render_body("resources_changed.html", %{dataset: dataset})
  end

  def new_comments(%DB.Contact{email: email}, datasets) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(email)
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject("Nouveaux commentaires")
    |> render_body("new_comments_reuser.html", %{datasets: datasets})
  end

  def promote_reuser_space(email) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(email)
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject("Gestion de vos favoris dans votre espace réutilisateur")
    |> render_body("promote_reuser_space.html")
  end
end
