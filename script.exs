url = "https://eu.ftp.opendatasoft.com/sncf/gtfs/export-ter-gtfs-last.zip"

Finch.start_link(name: MyFinch)
request = Finch.build(:get, url)

{:ok, result} = Finch.stream(request, MyFinch, %{}, fn(tuple, acc) ->
  case tuple do
    {:status, status} ->
      acc
      |> Map.put(:status, status)
      |> Map.put(:hash, :crypto.hash_init(:sha256))
      |> Map.put(:body_byte_size, 0)
    {:headers, headers} ->
      acc
      |> Map.put(:headers, headers)
      acc
    {:data, data} ->
      hash = :crypto.hash_update(acc.hash, data)
      %{acc | hash: hash, body_byte_size: acc[:body_byte_size] + (data |> byte_size)}
  end
end)

hash = result[:hash]
|> :crypto.hash_final()
|> Base.encode16()
|> String.downcase()

result = %{result | hash: hash}

IO.inspect result

IO.puts "Legacy computation:"
IO.puts Hasher.compute_sha256(url)
IO.puts Hasher.compute_sha256(url)
