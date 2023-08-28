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

  test "it works" do
    url = Path.join(@host, "/api/datasets")

    %{status: 200, body: json} = Query.cached_get!(url)

    api_spec = TransportWeb.API.Spec.spec()

    assert_schema(json, "DatasetsResponse", api_spec)

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
        on_timeout: :kill_task
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Enum.into([])

    datasets
    |> Enum.each(fn d ->
      assert_schema(d, "DatasetDetails", api_spec)
    end)
  end
end
