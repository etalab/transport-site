# Very preliminary use of ExMachina to generate test records.
# We should figure out how to use changeset validations here, but
# so far various troubles have been met.
defmodule TransportWeb.Factory do
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
      # NOTE: need to figure out how to pass aom/region together with changeset checks here
      datagouv_id: "123",
      aom: build(:aom)
    }
  end

  # Non-Ecto stuff, for now kept here for convenience

  def datagouv_api_get_factory do
    %{
      "title" => "some title"
    }
  end
end
