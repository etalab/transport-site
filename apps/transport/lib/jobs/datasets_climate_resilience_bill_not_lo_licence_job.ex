defmodule Transport.Jobs.DatasetsClimateResilienceBillNotLOLicenceJob do
  @moduledoc """
  Job in charge of sending email notifications to our bizdev team
  when datasets are subject to a compulsory data integration obligation (article 122)
  and switched to an inappropriate licence.
  """
  use Oban.Worker, max_attempts: 3, tags: ["moderation"]
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    datasets = relevant_datasets()
    remove_climate_resilience_bill_tag(datasets)

    unless Enum.empty?(datasets) do
      Transport.EmailSender.impl().send_mail(
        "transport.data.gouv.fr",
        Application.get_env(:transport, :contact_email),
        Application.get_env(:transport, :bizdev_email),
        Application.get_env(:transport, :contact_email),
        "Jeux de données article 122 avec licence inappropriée",
        "",
        Phoenix.View.render_to_string(
          TransportWeb.EmailView,
          "datasets_climate_resilience_bill_inappropriate_licence.html",
          datasets: datasets
        )
      )
    end

    :ok
  end

  def relevant_datasets do
    DB.Dataset.base_query()
    |> DB.Dataset.filter_by_custom_tag("loi-climat-resilience")
    |> DB.Repo.all()
    |> Enum.reject(&DB.Dataset.has_licence_ouverte?/1)
  end

  def remove_climate_resilience_bill_tag(datasets) do
    ids = Enum.map(datasets, & &1.id)

    DB.Dataset.base_query()
    |> where([dataset: d], d.id in ^ids)
    |> update([dataset: d], set: [custom_tags: fragment("array_remove(?, 'loi-climat-resilience')", d.custom_tags)])
    |> DB.Repo.update_all([])
  end
end
