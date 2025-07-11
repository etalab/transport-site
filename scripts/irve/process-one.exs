url = "https://www.data.gouv.fr/fr/datasets/r/df320cfa-6fca-4489-a652-328945897f21"

%{status: 200, body: body} = Transport.IRVE.RawStaticConsolidation.download_resource_content!(url)

Transport.IRVE.RawStaticConsolidation.run_cheap_blocking_checks(body, ".csv")

output = Transport.IRVE.Processing.read_as_data_frame(body)

IO.inspect(output, IEx.inspect_opts)
