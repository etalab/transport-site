Mix.install([
  {:req, "~> 0.4.0"}
])

large_file_url = "https://www.data.gouv.fr/fr/datasets/r/c83ba91e-2cd1-40f7-a632-eb0a76d83c49"
# small_file_url = "https://httpbin.org/range/100000"

url = large_file_url
# url = small_file_url

# Download file to disk via an IO.Stream
file = File.stream!("test.data", [:write])
try do
  # NOTE: decode_body is apparently disabled on response streaming
  # https://hexdocs.pm/req/Req.Steps.html#decode_body/1
  response = Req.get!(url, into: file)
  # :body is just a ref to the File.Stream
  IO.inspect(response, IEx.inspect_opts)
after
  :ok = File.close(file)
end
