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
      nom: "Pays de la Loire"
    }
  end

  def aom_factory do
    %DB.AOM{
      insee_commune_principale: "38185",
      nom: "Grenoble",
      region: build(:region),
      # The value must be unique, ExFactory helps us with a named sequence
      composition_res_id: sequence("composition_res_id", & &1)
    }
  end

  def dataset_factory do
    %DB.Dataset{
      datagouv_title: "Hello",
      slug: sequence("dataset_slug", fn i -> "dataset-#{i}" end),
      # NOTE: need to figure out how to pass aom/region together with changeset checks here
      datagouv_id: "123",
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

  def validation_factory do
    %DB.Validation{}
  end

  def geo_data_import_factory do
    %DB.GeoDataImport{}
  end

  # Non-Ecto stuff, for now kept here for convenience

  def datagouv_api_get_factory do
    %{
      "title" => "some title"
    }
  end
end
