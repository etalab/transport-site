#! mix run
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
  @index_url Path.join(@host, "/api/datasets")

  def api_spec, do: TransportWeb.API.Spec.spec()

  test "/api/datasets passes our OpenAPI specification" do
    url = @index_url
    %{status: 200, body: json} = Query.cached_get!(url)
    assert_schema(json, "DatasetsResponse", api_spec())
  end

  test "each /api/datasets/:id passes our OpenAPI specification" do
    url = @index_url
    %{status: 200, body: json} = Query.cached_get!(url)

    task = fn id ->
      # IO.puts("Processing #{id}")
      url = Path.join(@host, "/api/datasets/#{id}")
      %{status: 200, body: json} = Query.cached_get!(url)
      json
    end

    datasets =
      json
      |> Enum.map(& &1["id"])
      |> Task.async_stream(
        task,
        max_concurrency: 25,
        on_timeout: :kill_task,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.into([])

    datasets
    |> Enum.each(fn d ->
      assert_schema(d, "DatasetDetails", api_spec())
    end)
  end
end
