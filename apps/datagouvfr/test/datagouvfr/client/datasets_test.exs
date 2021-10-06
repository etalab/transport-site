defmodule Datagouvfr.Client.DatasetsTest do
  use Datagouvfr.ConnCase, async: false
  use Datagouvfr.ExternalCase
  alias Datagouvfr.Client
  alias Datagouvfr.Client.Datasets

  doctest Client

  setup do
    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)
    :ok
  end

  test "get one dataset" do
    use_cassette "client/datasets/one-0" do
      assert "5387f0a0a3a7291cb367549e" == Datasets.get_id_from_url("horaires-et-arrets-du-reseau-irigo-format-gtfs")
    end
  end
end
