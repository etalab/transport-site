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
      title: "Hello",
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
    %DB.ResourceHistory{version: "1"}
  end

  def commune_factory do
    %DB.Commune{
      nom: "Ballans",
      insee: "17031"
    }
  end

  # Non-Ecto stuff, for now kept here for convenience

  def datagouv_api_get_factory do
    %{
      "title" => "some title"
    }
  end
end
