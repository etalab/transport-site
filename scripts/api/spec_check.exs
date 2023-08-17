Code.require_file(__DIR__ <> "/../irve/req_custom_cache.exs")

ExUnit.start()

defmodule Query do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  def cached_get!(url) do
    req = Req.new() |> CustomCache.attach()
    Req.get!(req, url: url, custom_cache_dir: cache_dir())
  end
end

defmodule TestSuite do
  use ExUnit.Case
  import OpenApiSpex.TestAssertions

  @host "https://transport.data.gouv.fr"

  test "it works" do
    url = Path.join(@host, "/api/datasets")

    %{status: 200, body: json} = Query.cached_get!(url)

    api_spec = TransportWeb.API.Spec.spec()

    json = Enum.take(json, 1)

    assert_schema(json, "DatasetsResponse", api_spec)
  end
end
