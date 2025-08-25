# a handy script to download a single IRVE URL, and try to read it as data frame,
# without having to go through the whole consolidation process.

url = "https://www.data.gouv.fr/api/1/datasets/r/d445f73a-797f-46ea-98cc-2927ec7a018d"

%{status: 200, body: body} = Transport.IRVE.RawStaticConsolidation.download_resource_content!(url)

# if needed, e.g. for https://github.com/etalab/transport-site/issues/4771
# body = Transport.IRVE.RawStaticConsolidation.maybe_convert_utf_16("689c957abf34e799e1bf365a", body)

Transport.IRVE.RawStaticConsolidation.run_cheap_blocking_checks(body, ".csv")

output = Transport.IRVE.Processing.read_as_data_frame(body)

IO.inspect(output, IEx.inspect_opts())
