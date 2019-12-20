defmodule Datagouvfr.Client.DatasetsTest do
  # smell
  use TransportWeb.ConnCase, async: false
  # smell
  use TransportWeb.ExternalCase
  alias Datagouvfr.Client
  alias Datagouvfr.Client.Datasets

  doctest Client

  test "get one dataset" do
    use_cassette "client/datasets/one-0" do
      assert "5387f0a0a3a7291cb367549e" == Datasets.get_id_from_url("horaires-et-arrets-du-reseau-irigo-format-gtfs")
    end
  end
end
