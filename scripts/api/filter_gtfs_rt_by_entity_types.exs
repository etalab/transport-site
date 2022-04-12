Mix.install([
  {:jason, "~> 1.3"},
  {:req, "~> 0.2.2"}
])

url = "https://transport.data.gouv.fr/api/datasets"
file = Regex.replace(~r/\W/, url, "-")

unless File.exists?(file) do
  %{status: 200, body: body} = Req.get!(url)
  File.write!(file, body |> Jason.encode!())
end

IO.puts("============= first attempt =============")

file
|> File.read!()
|> Jason.decode!()
|> Enum.map(& &1["resources"])
|> List.flatten()
|> Enum.filter(&("service_alerts" in &1["features"]))
# NOTE: we lack a `page_url` or reliable ressource id to
# build a link back to the site here
# https://github.com/etalab/transport-site/issues/2303
|> IO.inspect(IEx.inspect_opts())

IO.puts("============= work-around for #2303 ==============")

# as a quick work-around, just report on the dataset page, which usually has only one GTFS-RT resource
file
|> File.read!()
|> Jason.decode!()
|> Enum.map(fn d ->
  resources = d["resources"] |> Enum.filter(&("service_alerts" in &1["features"]))

  if resources == [] do
    nil
  else
    d["page_url"]
  end
end)
|> Enum.reject(&is_nil/1)
|> Enum.join("\n")
|> IO.puts()
