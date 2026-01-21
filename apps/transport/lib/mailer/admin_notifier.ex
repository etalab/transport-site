defmodule Transport.AdminNotifier do
  @moduledoc """
  Module in charge of building emails sent to the admin team (bizdev, tech, etc.)
  """
  use Phoenix.Swoosh, view: TransportWeb.EmailView, layout: {TransportWeb.LayoutView, :email}
  import Transport.Expiration, only: [delay_str: 2]

  def contact(email, user_type, question_type, subject, question) do
    notify_contact("PAN, Formulaire Contact", email)
    |> subject(subject)
    |> render_body("contact.html", user_type: user_type, question_type: question_type, question: question)
  end

  def feedback(rating, explanation, email, feature) do
    rating_t = %{like: "j’aime", neutral: "neutre", dislike: "mécontent"}

    reply_email = if email, do: email, else: Application.fetch_env!(:transport, :contact_email)

    notify_contact("Formulaire feedback", reply_email)
    |> subject("Nouvel avis pour #{feature} : #{rating_t[rating]}")
    |> render_body("feedback.html",
      feature: feature,
      rating: rating_t[rating],
      email_address: email,
      explanation: explanation
    )
  end

  def bnlc_consolidation_report(subject, body, file_url) do
    notify_bizdev()
    |> subject(subject)
    |> render_body("bnlc_consolidation_report.html", body: body, file_url: file_url)
  end

  def datasets_without_gtfs_rt_related_resources(datasets) do
    notify_bizdev()
    |> subject("Jeux de données GTFS-RT sans ressources liées")
    |> render_body("datasets_without_gtfs_rt_related_resources.html",
      list: Enum.map_join(datasets, "", &link_and_name/1)
    )
  end

  def unknown_gbfs_operator_feeds(resources) do
    notify_bizdev()
    |> subject("Flux GBFS : opérateurs non détectés")
    |> render_body("unknown_gbfs_operator_feeds.html",
      list: Enum.map(resources, fn %DB.Resource{url: url} -> ~s|<li><a href="#{url}">#{url}</a></li>| end)
    )
  end

  def datasets_climate_resilience_bill_inappropriate_licence(datasets) do
    notify_bizdev()
    |> subject("Jeux de données article 122 avec licence inappropriée")
    |> render_body("datasets_climate_resilience_bill_inappropriate_licence.html", %{datasets: datasets})
  end

  def new_datagouv_datasets(category, datagouv_datasets, rule_explanation, duration) do
    notify_bizdev()
    |> subject("Nouveaux jeux de données #{category} à référencer - data.gouv.fr")
    |> render_body("new_datagouv_datasets.html",
      list: Enum.map_join(datagouv_datasets, "", &link_and_name_from_datagouv_payload/1),
      rule_explanation: rule_explanation,
      duration: duration
    )
  end

  def expiration(records) do
    notify_bizdev()
    |> subject("Jeux de données arrivant à expiration")
    |> render_body("expiration.html", expiration: Enum.map_join(records, "<hr>", &expiration_str/1))
  end

  def inactive_datasets(reactivated_datasets, inactive_datasets, archived_datasets) do
    notify_bizdev()
    |> subject("Jeux de données supprimés ou archivés")
    |> render_body("inactive_datasets.html",
      inactive_datasets_str: fmt_inactive_datasets(inactive_datasets),
      reactivated_datasets_str: fmt_reactivated_datasets(reactivated_datasets),
      archived_datasets_str: fmt_archived_datasets(archived_datasets)
    )
  end

  def oban_failure(worker) do
    notify_tech()
    |> subject("Échec de job Oban : #{worker}")
    |> render_body("oban_failure.html", worker: worker)
  end

  # Utility functions from here

  defp notify_bizdev do
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
