defmodule Transport.Jobs.ImportDatasetContactPointsJob do
  @moduledoc """
  Import dataset contact points coming from the data.gouv.fr's API.

  Producers can specify contact points for a dataset on their open data
  platform or directly on data.gouv.fr.

  We reuse this data to find or create contacts and subscribe these contacts
  to producer subscriptions for this dataset.

  When a contact point was previously set and has been removed,
  we delete old subscriptions.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  require Logger

  # The number of workers to run in parallel
  @task_concurrency 5
  # The source when creating a contact
  @contact_source :"automation:import_contact_point"
  # The notification subscription source when creating/deleting subscriptions
  @notification_subscription_source "automation:import_contact_point"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    dataset_datagouv_ids()
    |> Task.async_stream(
      &import_contact_point/1,
      max_concurrency: @task_concurrency,
      on_timeout: :kill_task,
      timeout: 10_000
    )
    |> Stream.run()
  end

  def dataset_datagouv_ids do
    DB.Dataset.base_query() |> select([dataset: d], d.datagouv_id) |> DB.Repo.all()
  end

  def import_contact_point(datagouv_id) do
    dataset = DB.Repo.get_by!(DB.Dataset, datagouv_id: datagouv_id)

    case Datagouvfr.Client.Datasets.get(datagouv_id) do
      {:ok, %{"contact_points" => contact_points}} ->
        update_contact_points(dataset, contact_points)

      other ->
        Logger.error("#{inspect(__MODULE__)} unexpected HTTP response for dataset##{datagouv_id}: #{inspect(other)}")
    end
  end

  @doc """
  iex> guess_identity("John DOE")
  %{first_name: "John", last_name: "DOE", mailing_list_title: nil}
  iex> guess_identity("DOE John")
  %{first_name: "John", last_name: "DOE", mailing_list_title: nil}
  iex> guess_identity("John Doe")
  %{first_name: "John", last_name: "Doe", mailing_list_title: nil}
  iex> guess_identity("Service géomatique open data")
  %{first_name: nil, last_name: nil, mailing_list_title: "Service géomatique open data"}
  iex> guess_identity("")
  %{first_name: nil, last_name: nil, mailing_list_title: "Inconnu"}
  """
  @spec guess_identity(binary() | nil) :: %{
          first_name: binary() | nil,
          last_name: binary() | nil,
          mailing_list_title: binary() | nil
        }
  def guess_identity(name) do
    cond do
      private_individual?(name) ->
        guess_first_and_last_name(name) |> Map.put(:mailing_list_title, nil)

      name not in ["", nil] ->
        %{first_name: nil, last_name: nil, mailing_list_title: name}

      true ->
        %{first_name: nil, last_name: nil, mailing_list_title: "Inconnu"}
    end
  end

  defp update_contact_points(%DB.Dataset{id: dataset_id}, []) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.dataset_id == ^dataset_id and ns.role == :producer and ns.source == ^@notification_subscription_source
    )
    |> DB.Repo.delete_all()
  end

  defp update_contact_points(%DB.Dataset{} = dataset, contact_points) do
    contacts = Enum.map(contact_points, &update_contact_point(dataset, &1))
    contact_ids = Enum.map(contacts, & &1.id)

    DB.NotificationSubscription.delete_other_producers_subscriptions(
      dataset,
      contact_ids,
      @notification_subscription_source
    )
  end

  defp update_contact_point(%DB.Dataset{} = dataset, %{"email" => _, "name" => _} = contact_point) do
    contact = find_or_create_contact(contact_point)
    DB.NotificationSubscription.create_producer_subscriptions(dataset, contact, @notification_subscription_source)
    contact
  end

  defp find_or_create_contact(%{"email" => email, "name" => name}) do
    case DB.Repo.get_by(DB.Contact, email_hash: String.downcase(email)) do
      %DB.Contact{} = contact ->
        contact

      nil ->
        Map.merge(guess_identity(name), %{email: email, creation_source: @contact_source})
        |> DB.Contact.insert!()
    end
  end

  defp private_individual?(nil), do: false

  defp private_individual?(name) do
    String.split(name, " ") |> Enum.count() == 2
  end

  defp guess_first_and_last_name(name) do
    [first, second] = values = String.split(name, " ")

    case Enum.map(values, &upcase?/1) do
      [false, true] ->
        %{first_name: first, last_name: second}

      [true, false] ->
        %{first_name: second, last_name: first}

      _ ->
        %{first_name: first, last_name: second}
    end
  end

  defp upcase?(value), do: value == String.upcase(value)
end
