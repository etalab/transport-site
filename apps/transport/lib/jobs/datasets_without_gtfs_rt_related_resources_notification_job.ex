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
    Transport.AdminNotifier.datasets_without_gtfs_rt_related_resources(datasets)
    |> Transport.Mailer.deliver()

    :ok
  end

  @doc """
  Find datasets for which we need to do something.

  These datasets have:
  - > 1 up-to-date GTFS
  - > 0 gtfs-rt resources
  - no resource related links set for GTFS-RT resources
  """
  def relevant_datasets do
    datasets_with_multiple_gtfs =
      DB.Dataset.base_query()
      |> DB.Dataset.join_from_dataset_to_metadata(
        Enum.map(
          Transport.ValidatorsSelection.validators_for_feature(:datasets_without_gtfs_rt_related_resouces),
          & &1.validator_name()
        )
      )
      |> DB.ResourceMetadata.where_up_to_date()
      |> where([resource: r], r.format == "GTFS" and not r.is_community_resource)
      |> group_by([dataset: d], d.id)
      |> having([resource: r], count(r.id) > 1)
      |> select([dataset: d], d.id)

    # Datasets with at least 1 GTFS-RT resource and > 1 up-to-date GTFS
    dataset_ids_sub =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> where(
        [resource: r],
        r.format == "gtfs-rt" and not r.is_community_resource and r.dataset_id in subquery(datasets_with_multiple_gtfs)
      )
      |> group_by([dataset: d], d.id)
      |> having([resource: r], count(r.id) > 0)
      |> select([dataset: d], d.id)

    # Datasets missing resource related rows and also part of the previous groups
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
