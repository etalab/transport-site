defmodule Transport.AdminNotifier do
  @moduledoc """
  Module in charge of building emails sent to the admin team (bizdev, tech, etc.)
  """
  use Phoenix.Swoosh, view: TransportWeb.EmailView

  def contact(email, subject, question) do
    notify_contact("PAN, Formulaire Contact", email)
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

    notify_contact("Formulaire feedback", reply_email)
    |> subject("Nouvel avis pour #{feature} : #{rating_t[rating]}")
    |> text_body(feedback_content)
  end

  def bnlc_consolidation_report(subject, body, file_url) do
    report_content = """
    #{body}
    <br/><br/>
    🔗 <a href="#{file_url}">Fichier consolidé</a>
    """

    notify_bidzev()
    |> subject(subject)
    |> html_body(report_content)
  end

  def datasets_without_gtfs_rt_related_resources(datasets) do
    notify_bidzev()
    |> subject("Jeux de données GTFS-RT sans ressources liées")
    |> html_body("""
    <p>Bonjour,</p>

    <p>Les jeux de données suivants contiennent plusieurs GTFS et des liens entre les ressources GTFS-RT et GTFS sont manquants :</p>

    <ul>
    #{Enum.map_join(datasets, "", &link_and_name/1)}
    </ul>

    <p>L’équipe transport.data.gouv.fr</p>
    """)
  end

  def datasets_climate_resilience_bill_inappropriate_licence(datasets) do
    notify_bidzev()
    |> subject("Jeux de données article 122 avec licence inappropriée")
    |> render_body("datasets_climate_resilience_bill_inappropriate_licence.html", %{datasets: datasets})
  end

  def new_datagouv_datasets(category, datagouv_datasets, rule_explanation, duration) do
    notify_bidzev()
    |> subject("Nouveaux jeux de données #{category} à référencer - data.gouv.fr")
    |> html_body("""
    <p>Bonjour,</p>

    <p>Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières #{duration}h et sont susceptibles d'avoir leur place sur le PAN :</p>

    <ul>
    #{Enum.map_join(datagouv_datasets, "", &link_and_name_from_datagouv_payload/1)}
    </ul>
    <br/>
    <hr>
    #{rule_explanation}
    <p>Vous pouvez modifier <a href="https://github.com/etalab/transport-site/blob/master/apps/transport/lib/jobs/new_datagouv_datasets_job.ex">les règles de cette tâche</a>.</p>
    """)
  end

  def expiration(records) do
    notify_bidzev()
    |> subject("Jeux de données arrivant à expiration")
    |> html_body("""
    <p>Bonjour,</p>

    <p>Voici un résumé des jeux de données arrivant à expiration</p>

    #{Enum.map_join(records, "<hr>", &expiration_str/1)}
    """)
  end

  def inactive_datasets(reactivated_datasets, inactive_datasets, archived_datasets) do
    reactivated_datasets_str = fmt_reactivated_datasets(reactivated_datasets)
    inactive_datasets_str = fmt_inactive_datasets(inactive_datasets)
    archived_datasets_str = fmt_archived_datasets(archived_datasets)

    notify_bidzev()
    |> subject("Jeux de données supprimés ou archivés")
    |> html_body("""
    <p>Bonjour,</p>
    #{inactive_datasets_str}
    #{reactivated_datasets_str}
    #{archived_datasets_str}

    <p>Il faut peut être creuser pour savoir si c'est normal.</p>
    """)
  end

  def oban_failure(worker) do
    notify_tech()
    |> subject("Échec de job Oban : #{worker}")
    |> text_body("Un job Oban #{worker} vient d'échouer, il serait bien d'investiguer.")
  end

  # Utility functions from here

  defp notify_bidzev do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    # Uses the contact@ email address but method is kept if we need
    # to route differently in the future.
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
  end

  defp notify_tech do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :tech_email))
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
  end

  defp notify_contact(form_name, email) do
    new()
    |> from({form_name, Application.fetch_env!(:transport, :contact_email)})
    |> to(Application.fetch_env!(:transport, :contact_email))
    |> reply_to(email)
  end

  defp expiration_str({delay, records}) do
    datasets = Enum.map(records, fn {%DB.Dataset{} = d, _} -> d end)

    dataset_str = fn %DB.Dataset{} = dataset ->
      link_and_name(dataset, " - #{expiration_notification_enabled_str(dataset)}#{climate_resilience_str(dataset)}")
    end

    """
    <p>Jeux de données #{delay_str(delay, :périmant)} :</p>

    <ul>
    #{Enum.map_join(datasets, "\n", &dataset_str.(&1))}
    </ul>
    """
  end

  def expiration_notification_enabled_str(%DB.Dataset{} = dataset) do
    if has_expiration_notifications?(dataset) do
      "✅ notification automatique"
    else
      "❌ pas de notification automatique"
    end
  end

  defp climate_resilience_str(%DB.Dataset{} = dataset) do
    if DB.Dataset.climate_resilience_bill?(dataset) do
      " ⚖️🗺️ article 122"
    else
      ""
    end
  end

  def has_expiration_notifications?(%DB.Dataset{} = dataset) do
    Transport.NotificationReason.reason(:expiration)
    |> DB.NotificationSubscription.subscriptions_for_reason_dataset_and_role(dataset, :producer)
    |> Enum.count() > 0
  end

  defp fmt_inactive_datasets([]), do: ""

  defp fmt_inactive_datasets(inactive_datasets) do
    """
    <p>Certains jeux de données ont disparus de data.gouv.fr :</p>
    <ul>
    #{Enum.map_join(inactive_datasets, "", &link_and_name/1)}
    </ul>
    """
  end

  defp fmt_reactivated_datasets([]), do: ""

  defp fmt_reactivated_datasets(reactivated_datasets) do
    """
    <p>Certains jeux de données disparus sont réapparus sur data.gouv.fr :</p>
    <ul>
    #{Enum.map_join(reactivated_datasets, "", &link_and_name/1)}
    </ul>
    """
  end

  defp fmt_archived_datasets([]), do: ""

  defp fmt_archived_datasets(archived_datasets) do
    """
    <p>Certains jeux de données sont indiqués comme archivés sur data.gouv.fr :</p>
    <ul>
    #{Enum.map_join(archived_datasets, "", &link_and_name/1)}
    </ul>

    <p>#{count_archived_datasets()} jeux de données sont archivés. Retrouvez-les <a href="#{backoffice_archived_datasets_url()}">dans le backoffice</a>.</p>
    """
  end

  def count_archived_datasets do
    DB.Dataset.archived() |> DB.Repo.aggregate(:count, :id)
  end

  defp backoffice_archived_datasets_url do
    TransportWeb.Router.Helpers.backoffice_page_url(TransportWeb.Endpoint, :index, %{"filter" => "archived"}) <>
      "#list_datasets"
  end

  @doc """
  Common to both notifiers. If refactored or moved elsewhere, don’t forget to change or delete Transport.NotifiersTest.
  iex> delay_str(0, :périmant)
  "périmant demain"
  iex> delay_str(0, :périment)
  "périment demain"
  iex> delay_str(2, :périmant)
  "périmant dans 2 jours"
  iex> delay_str(2, :périment)
  "périment dans 2 jours"
  iex> delay_str(-1, :périmant)
  "périmé depuis hier"
  iex> delay_str(-1, :périment)
  "sont périmées depuis hier"
  iex> delay_str(-2, :périmant)
  "périmés depuis 2 jours"
  iex> delay_str(-2, :périment)
  "sont périmées depuis 2 jours"
  iex> delay_str(-60, :périment)
  "sont périmées depuis 60 jours"
  """
  @spec delay_str(integer(), :périment | :périmant) :: binary()
  def delay_str(0, verb), do: "#{verb} demain"
  def delay_str(1, verb), do: "#{verb} dans 1 jour"
  def delay_str(d, verb) when d >= 2, do: "#{verb} dans #{d} jours"
  def delay_str(-1, :périmant), do: "périmé depuis hier"
  def delay_str(-1, :périment), do: "sont périmées depuis hier"
  def delay_str(d, :périmant) when d <= -2, do: "périmés depuis #{-d} jours"
  def delay_str(d, :périment) when d <= -2, do: "sont périmées depuis #{-d} jours"

  defp link_and_name_from_datagouv_payload(%{"title" => title, "page" => page}) do
    link = Phoenix.HTML.Link.link(title, to: page) |> Phoenix.HTML.safe_to_string()
    "<li>#{link}</li>"
  end

  @spec link_and_name(DB.Dataset.t(), binary()) :: binary()
  defp link_and_name(%DB.Dataset{slug: slug, custom_title: custom_title}, extra_content \\ "") do
    url = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    link = Phoenix.HTML.Link.link(custom_title, to: url) |> Phoenix.HTML.safe_to_string()
    "<li>#{link}#{extra_content}</li>"
  end
end
