# https://www.data.gouv.fr/fr/datasets/623ca46c13130c3228abd018/ - Electra dataset (mid-sized)
# https://www.data.gouv.fr/fr/datasets/623ca46c13130c3228abd018/#/resources/e9bb3424-77cd-40ba-8bbd-5a19362d0365

sample_url = "https://www.data.gouv.fr/fr/datasets/r/e9bb3424-77cd-40ba-8bbd-5a19362d0365"

# Note: cached in development if you set `irve_consolidation_caching: true` in `dev.secret.exs`
%Req.Response{status: 200, body: body} =
  Transport.IRVE.Fetcher.get!(sample_url, compressed: false, decode_body: false)

Transport.IRVE.DataFrame.dataframe_from_csv_body!(body)
|> IO.inspect(IEx.inspect_opts)
