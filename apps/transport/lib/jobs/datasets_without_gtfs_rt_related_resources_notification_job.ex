defmodule Transport.Jobs.DatasetsWithoutGTFSRTRelatedResourcesNotificationJob do
  @moduledoc """
  Job in charge of detecting datasets with missing related resources
  for GTFS-RT resources and sending a notification email to our team.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_datasets() |> send_email()
  end

  def send_email([]), do: :ok

  def send_email(datasets) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données GTFS-RT sans ressources liées",
      """
      Bonjour,

      Les jeux de données suivants contiennent plusieurs GTFS et des liens entre les ressources GTFS-RT et GTFS sont manquants :

      #{Enum.map_join(datasets, "\n", &link/1)}

      L’équipe transport.data.gouv.fr
      """,
      ""
    )

    :ok
  end

  def link(%DB.Dataset{slug: slug, custom_title: custom_title}) do
    link = TransportWeb.Router.Helpers.dataset_url(TransportWeb.Endpoint, :details, slug)
    "* #{custom_title} - #{link}"
  end

  def relevant_datasets do
    dataset_ids_sub =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> where([resource: r], not r.is_community_resource)
      |> group_by([dataset: d], d.id)
      |> having(
        [resource: r],
        # > 1 GTFS and >= 1 GTFS-RT
        fragment(
          ~s{sum(case when ? = 'GTFS' then 1 else 0 end) > 1 and sum(case when ? = 'gtfs-rt' then 1 else 0 end) >= 1},
          r.format,
          r.format
        )
      )
      |> select([dataset: d], d.id)

    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> join(:left, [resource: r], rr in DB.ResourceRelated,
      on: rr.resource_src_id == r.id and rr.reason == :gtfs_rt_gtfs,
      as: :resource_related
    )
    |> where(
      [resource: r, resource_related: rr, dataset: d],
      r.format == "gtfs-rt" and is_nil(rr.reason) and d.id in subquery(dataset_ids_sub)
    )
    |> distinct(true)
    |> select([dataset: d], d)
    |> order_by([dataset: d], asc: d.custom_title)
    |> DB.Repo.all()
  end
end
