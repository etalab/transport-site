IO.puts("OK")

# https://www.data.gouv.fr/fr/datasets/623ca46c13130c3228abd018/ - Electra dataset (mid-sized)
# https://www.data.gouv.fr/fr/datasets/623ca46c13130c3228abd018/#/resources/e9bb3424-77cd-40ba-8bbd-5a19362d0365

sample_url = "https://www.data.gouv.fr/fr/datasets/r/e9bb3424-77cd-40ba-8bbd-5a19362d0365"

# Note: cached in development if you set `irve_consolidation_caching: true` in `dev.secret.exs`
%Req.Response{status: 200, body: body} =
  Transport.IRVE.Fetcher.get!(sample_url, compressed: false, decode_body: false)

schema_file = "apps/shared/meta/schema-irve-statique.json"

# temporary mapper
type_mapper = fn
  # TODO: extract individual coordinates
  :geopoint -> :string
  # works for this specific case
  :number -> {:u, 16}
  type -> type
end

dtypes =
  schema_file
  |> File.read!()
  |> Jason.decode!()
  |> Map.fetch!("fields")
  |> Enum.map(fn %{"name" => name, "type" => type} ->
    {String.to_atom(name), String.to_atom(type) |> type_mapper.()}
  end)

IO.inspect(dtypes, IEx.inspect_opts())

df =
  Explorer.DataFrame.load_csv!(body,
    dtypes: dtypes
  )

IO.inspect(df, IEx.inspect_opts())
