Mix.install([
  {:req, "~> 0.3.0"}
])

Code.require_file(__DIR__ <> "/irve/req_custom_cache.exs")

defmodule HTTP do
  def get!(url, cache_dir: cache_dir) do
    url = URI.encode(url)
    req = Req.new()

    opts = [url: url]

    {req, opts} =
      if cache_dir do
        {req |> CustomCache.attach(), Keyword.put(opts, :custom_cache_dir, cache_dir)}
      else
        {req, opts}
      end

    %{body: body, status: 200} = Req.get!(req, opts)
    body
  end
end

url = "http://localhost:5000/api/datasets"
main_cache_dir = Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

datagouv_ids =
  HTTP.get!(url, cache_dir: main_cache_dir)
  |> Enum.map(fn x -> x["datagouv_id"] end)

defmodule Benchmark do
  def time_taken(cb) do
    {delay, result} = :timer.tc(cb)
    {delay / 1_000_000.0, result}
  end
end

task = fn id ->
  url = "http://localhost:5000/api/datasets/" <> id
  {delay_1, before_data} = Benchmark.time_taken(fn -> HTTP.get!(url, cache_dir: nil) end)
  File.write!("dataset-#{id}.json", before_data |> Jason.encode!())

  url = "http://localhost:5000/api/datasets/" <> id <> "?skip=1"
  {delay_2, after_data} = Benchmark.time_taken(fn -> HTTP.get!(url, cache_dir: nil) end)

  File.write!("dataset-#{id}-skip.json", after_data |> Jason.encode!())

  same_data = before_data == after_data

  message = "Processing #{id} (#{delay_1}, #{delay_2}, same_data=#{same_data})"
  gain = delay_1 - delay_2

  message =
    if gain > 0.25, do: message <> " (would gain #{gain |> Float.ceil(2)} seconds)", else: message

  IO.puts(message)

  unless before_data == after_data do
    # NOTE: this can fail (rarely) due to ordering of the records, but the sorted content is the same
    # if you compare files with `jd -set` (https://stackoverflow.com/a/40983522)
    IO.puts("================ Different returns found for #{id} =========================")
  end
end

datagouv_ids
|> Task.async_stream(
  task,
  max_concurrency: 10,
  on_timeout: :kill_task
)
|> Stream.run()
