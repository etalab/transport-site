defmodule Datagouvfr.Client.DatasetsTest do
  use TransportWeb.ConnCase, async: true
  alias Datagouvfr.Client
  alias Datagouvfr.Client.Datasets
  import Mox
  doctest Client

  setup :verify_on_exit!

  test "get one dataset" do
    id = Ecto.UUID.generate()
    slug = "slug" <> Ecto.UUID.generate()
    url = "https://demo.data.gouv.fr/api/1/datasets/#{slug}/"

    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{id: id})}}
    end)

    assert id == Datasets.get_id_from_url(slug)
  end
end
