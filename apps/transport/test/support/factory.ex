defmodule DB.Factory do
  @moduledoc """
  Very preliminary use of ExMachina to generate test records.
  We should figure out how to use changeset validations here, but
  so far various troubles have been met.
  """
  use ExMachina.Ecto, repo: DB.Repo

  # Ecto records

  def region_factory do
    %DB.Region{
      nom: sequence("region_nom")
    }
  end

  def aom_factory do
    %DB.AOM{
      insee_commune_principale: "38185",
      nom: "Grenoble",
      region: build(:region),
      # The value must be unique, ExFactory helps us with a named sequence
      composition_res_id: 1000 + sequence("composition_res_id", & &1)
    }
  end

  def dataset_factory do
    %DB.Dataset{
      datagouv_title: "Hello",
      slug: sequence(:slug, fn i -> "dataset_slug_#{i}" end),
      datagouv_id: sequence(:datagouv_id, fn i -> "dataset_datagouv_id_#{i}" end),
      # NOTE: need to figure out how to pass aom/region together with changeset checks here
      aom: build(:aom),
      tags: []
    }
  end

  def resource_factory do
    %DB.Resource{
      title: "GTFS.zip",
      latest_url: "url"
    }
  end

  def resource_history_factory do
    %DB.ResourceHistory{
      datagouv_id: "resource_datagouv_id_123",
      payload: %{}
    }
  end

  def data_conversion_factory do
    %DB.DataConversion{}
  end

  def resource_unavailability_factory do
    %DB.ResourceUnavailability{}
  end

  def metrics_factory do
    %DB.Metrics{}
  end

  def commune_factory do
    %DB.Commune{
      nom: "Ballans",
      insee: "17031"
    }
  end

  def data_import_factory do
    %DB.DataImport{}
  end

  def gtfs_stop_times_factory do
    %DB.GTFS.StopTimes{}
  end

  def gtfs_trips_factory do
    %DB.GTFS.Trips{}
  end

  def gtfs_calendar_factory do
    %DB.GTFS.Calendar{}
  end

  def gtfs_calendar_dates_factory do
    %DB.GTFS.CalendarDates{}
  end

  def geo_data_import_factory do
    %DB.GeoDataImport{}
  end

  def geo_data_factory do
    %DB.GeoData{}
  end

  def multi_validation_factory do
    %DB.MultiValidation{validator: "validator", validation_timestamp: DateTime.utc_now()}
  end

  def resource_metadata_factory do
    %DB.ResourceMetadata{}
  end

  def dataset_history_factory do
    %DB.DatasetHistory{}
  end

  def dataset_history_resources_factory do
    %DB.DatasetHistoryResources{}
  end

  def notification_factory do
    %DB.Notification{}
  end

  # Non-Ecto stuff, for now kept here for convenience

  def datagouv_api_get_factory do
    %{
      "title" => "some title"
    }
  end

  @doc """
  Useful function to insert in one call everything needed for resource related tests.
  A dataset, a resource, a resource history, a multi_validation, some metadata
  For the moment, it inserts GTFS resources, but could be extended to insert any resource type and validation.

  Usage:
  insert_resource_and_friends(~D[2022-07-12], [])
  => insert an active dataset, a resource, a resource history, a validation, a metadata.
  Metadata contains the end date provided.

  insert_resource_and_friends(~D[2022-07-12], [is_active: false])
  => same as above, but the dataset is inactive

  insert_resource_and_friends(~D[2022-07-12], [resource_available: false])
  => resource is inserted with is_available = false

  insert_resource_and_friends(~D[2022-07-12], [resource_history_payload: %{"url" => "xxx"}])
  => specify resource_history payload

  insert_resource_and_friends(~D[2022-07-12], [dataset: dataset_1])
  => provide an already existing dataset. Useful when inserting a second resource linked to a dataset.

  The function returns a map with all the created DB structures
  """
  def insert_resource_and_friends(end_date, opts) do
    def_opts = [resource_available: true, is_active: true, resource_history_payload: %{}]
    opts = Keyword.merge(def_opts, opts)

    dataset_opts = [
      is_active: Keyword.get(opts, :is_active),
      region_id: Keyword.get(opts, :region_id),
      has_realtime: Keyword.get(opts, :has_realtime),
      type: Keyword.get(opts, :type),
      aom: Keyword.get(opts, :aom),
      custom_title: Keyword.get(opts, :custom_title)
    ]

    dataset_opts =
      case Keyword.get(opts, :aom) do
        nil -> dataset_opts
        aom -> dataset_opts |> Keyword.merge(aom: aom)
      end

    dataset = Keyword.get(opts, :dataset, insert(:dataset, dataset_opts))

    %{id: resource_id} =
      resource =
      Keyword.get(
        opts,
        :resource,
        insert(:resource,
          dataset_id: dataset.id,
          is_available: Keyword.get(opts, :resource_available),
          format: "GTFS",
          datagouv_id: Ecto.UUID.generate()
        )
      )

    resource_history =
      insert(:resource_history, resource_id: resource_id, payload: Keyword.get(opts, :resource_history_payload))

    multi_validation =
      insert(:multi_validation,
        validator: Transport.Validators.GTFSTransport.validator_name(),
        resource_history_id: resource_history.id,
        max_error: Keyword.get(opts, :max_error)
      )

    resource_metadata =
      insert(:resource_metadata,
        multi_validation_id: multi_validation.id,
        metadata: %{"start_date" => end_date |> Date.add(-60), "end_date" => end_date},
        modes: Keyword.get(opts, :modes),
        features: Keyword.get(opts, :features)
      )

    %{
      dataset: dataset,
      resource: resource,
      resource_history: resource_history,
      multi_validation: multi_validation,
      resource_metadata: resource_metadata
    }
  end

  def insert_up_to_date_resource_and_friends(opts \\ []) do
    insert_resource_and_friends(Date.utc_today() |> Date.add(30), opts)
  end

  def insert_outdated_resource_and_friends(opts \\ []) do
    insert_resource_and_friends(Date.utc_today() |> Date.add(-5), opts)
  end

  def insert_notification(%{dataset: %DB.Dataset{id: dataset_id, datagouv_id: datagouv_id}} = args) do
    args
    |> Map.delete(:dataset)
    |> Map.merge(%{dataset_id: dataset_id, dataset_datagouv_id: datagouv_id})
    |> insert_notification()
  end

  def insert_notification(args) do
    %DB.Notification{}
    |> DB.Notification.changeset(args)
    |> DB.Repo.insert!()
  end

  def notification_subscription_factory do
    %DB.NotificationSubscription{}
  end
end
