defmodule Unlock.Plugs.TokenAuthTest do
  use ExUnit.Case, async: false
  import DB.Factory
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint
  import Mox

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    detach_telemetry_handlers()
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "valid token passed" do
    slug = "an-existing-identifier"
    %DB.Token{id: token_id} = token = insert_token()

    setup_proxy_config(%{
      slug => %Unlock.Config.Item.Generic.HTTP{
        identifier: slug,
        target_url: target_url = "http://localhost/some-remote-resource",
        ttl: 30
      }
    })

    Unlock.HTTP.Client.Mock
    |> expect(:get!, fn url, _headers = [], _options = [] ->
      assert url == target_url
      %Unlock.HTTP.Response{body: "somebody-to-love", status: 200, headers: []}
    end)

    resp = build_conn() |> get("/resource/#{slug}?token=#{token.secret}")

    assert resp.resp_body == "somebody-to-love"
    assert %DB.Token{id: ^token_id} = resp.assigns[:token]

    assert [
             %DB.ProxyRequest{proxy_id: ^slug, token_id: ^token_id}
           ] = DB.ProxyRequest |> DB.Repo.all()
  end

  test "no token passed" do
    slug = "another-identifier"

    setup_proxy_config(%{
      slug => %Unlock.Config.Item.Generic.HTTP{
        identifier: slug,
        target_url: target_url = "http://localhost/some-remote-resource",
        ttl: 30
      }
    })

    Unlock.HTTP.Client.Mock
    |> expect(:get!, fn url, _headers = [], _options = [] ->
      assert url == target_url
      %Unlock.HTTP.Response{body: "somebody-to-love", status: 200, headers: []}
    end)

    resp = build_conn() |> get("/resource/#{slug}")

    assert resp.resp_body == "somebody-to-love"
    assert is_nil(resp.assigns[:token])

    assert [] = DB.ProxyRequest |> DB.Repo.all()
  end

  test "invalid token passed" do
    resp = build_conn() |> get("/resource/slug?token=invalid")

    assert resp.status == 401
    assert resp.resp_body == ~s|{"error":"You must set a valid token in the query parameters"}|

    assert DB.ProxyRequest |> DB.Repo.all() == []
  end

  defp setup_proxy_config(config) do
    Unlock.Config.Fetcher.Mock |> stub(:fetch_config!, fn -> config end)
  end

  defp detach_telemetry_handlers do
    events = Unlock.Telemetry.proxy_request_event_names()

    # NOTE: this is deregistering the `apps/transport`
    # handlers, which will otherwise create Ecto records.
    events
    |> Enum.flat_map(&:telemetry.list_handlers(&1))
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.each(&:telemetry.detach/1)
  end
end
