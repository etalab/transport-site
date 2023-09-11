Mix.install([
  {:req, "~> 0.4.0"}
])

_large_file_url = "https://www.data.gouv.fr/fr/datasets/r/c83ba91e-2cd1-40f7-a632-eb0a76d83c49"
small_file_url = "https://httpbin.org/range/100000"

url = _large_file_url

# downloading directly to disk
file = File.stream!("test.data", [:write])
response = Req.get!(large_file_url, into: file)
File.close(file)
# the body is not here (well it is, but as a stream)
IO.inspect(response, IEx.inspect_opts)

IO.puts "ok"
