Mix.install([
  {:req, "~> 0.3.6"},
  {:yaml_elixir, "~> 2.9"}
])

IO.puts("starting...")

"config/proxy-config.yml"
|> File.read!()
|> YamlElixir.read_from_string!()
|> Map.fetch!("feeds")
|> Enum.filter(&(&1["type"] == "generic-http"))
|> Enum.map(&"http://proxy.localhost:5000/resource/#{&1["identifier"]}")
# |> IO.inspect(IEx.inspect_opts)
# |> Enum.take(1)
|> Enum.each(fn url ->
  IO.puts("\n============= #{url} =============")

  resp = Req.get!(url)

  IO.inspect(resp.status)
  IO.inspect(resp.headers)
  IO.inspect(resp.body, printable_limit: 100)
end)
