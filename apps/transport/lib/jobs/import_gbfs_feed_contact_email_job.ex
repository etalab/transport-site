defmodule Transport.Jobs.ImportGBFSFeedContactEmailJob do
  @moduledoc """
  Reuse `feed_contact_email` from GBFS feeds.

  Use these email addresses to find or create a contact and subscribe this contact
  to producer subscriptions for this dataset.

  When a `feed_contact_point` was previously set and changed,
  we delete old subscriptions and create new ones.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  require Logger

  # The source when creating a contact
  @contact_source :"automation:import_gbfs_feed_contact_email"
  # The notification subscription source when creating/deleting subscriptions
  @notification_subscription_source :"automation:gbfs_feed_contact_email"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    gbfs_feed_contact_emails() |> Enum.each(&update_feed_contact_email/1)
  end

  def update_feed_contact_email(
        %{
          resource_url: _,
          dataset_id: dataset_id,
          feed_contact_email: _
        } = params
      ) do
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)
    contact = find_or_create_contact(params)
    DB.NotificationSubscription.create_producer_subscriptions(dataset, contact, @notification_subscription_source)

    DB.NotificationSubscription.delete_other_producers_subscriptions(
      dataset,
      contact,
      @notification_subscription_source
    )
  end

  defp find_or_create_contact(%{resource_url: resource_url, feed_contact_email: feed_contact_email}) do
    case DB.Repo.get_by(DB.Contact, email_hash: String.downcase(feed_contact_email)) do
      %DB.Contact{} = contact ->
        contact

      nil ->
        %{
          mailing_list_title: contact_title(resource_url),
          email: feed_contact_email,
          creation_source: @contact_source,
          organization: Transport.GBFSMetadata.operator(resource_url)
        }
        |> DB.Contact.insert!()
    end
  end

  @doc """
  iex> contact_title("https://api.cyclocity.fr/contracts/nantes/gbfs/gbfs.json")
  "Équipe technique GBFS JC Decaux"
  iex> contact_title("https://example.com/gbfs.json")
  "Équipe technique GBFS Example"
  iex> contact_title("https://404.fr")
  "Équipe technique GBFS"
  """
  def contact_title(resource_url) do
    operator_name = Transport.GBFSMetadata.operator(resource_url) || ""
    "Équipe technique GBFS #{operator_name}" |> String.trim()
  end

  @doc """
  Finds feed contact emails for GBFS feeds.
  Uses the metadata collected by `Transport.GBFSMetadata` over the last week.
  """
  def gbfs_feed_contact_emails do
    last_week = DateTime.utc_now() |> DateTime.add(-7, :day)

    DB.ResourceMetadata.base_query()
    |> join(:inner, [metadata: m], r in DB.Resource, on: r.id == m.resource_id, as: :resource)
    |> where([resource: r], r.format == "gbfs")
    |> where(
      [metadata: m],
      m.inserted_at >= ^last_week and fragment("?->'system_details' \\? 'feed_contact_email'", m.metadata)
    )
    |> select([metadata: m, resource: r], %{
      resource_id: r.id,
      resource_url: r.url,
      dataset_id: r.dataset_id,
      feed_contact_email:
        last_value(fragment("?->'system_details'->> 'feed_contact_email'", m.metadata))
        |> over(partition_by: m.resource_id, order_by: m.resource_id)
    })
    |> distinct(true)
    |> DB.Repo.all()
  end
end
