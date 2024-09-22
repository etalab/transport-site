[file] = Path.wildcard("../*.log")

IO.inspect(file, IEx.inspect_opts())

defmodule LogCategorize do
  def categorize(line) do
    #    IO.write(line)

    cond do
      line =~ ~r/path=\/gbfs/ ->
        "/path/gbfs"

      line =~ ~r/GET \/gbfs/ ->
        "GET /path/gbfs"

      line =~ ~r/(GET|HEAD) \/resource\// ->
        "proxy:resource:get"

      line =~ ~r/Telemetry event\: processing .* proxy request/ ->
        "telemetry:proxy"

      line =~ ~r/Proxy response for/ ->
        "proxy:response"

      line =~ ~r/Processing proxy request for identifier/ ->
        "proxy:processing"

      line =~ ~r/Sent 200 in/ ->
        "response:200"

      line =~ ~r/Sent 404 in/ ->
        "response:404"

      true ->
        # IO.write(line)
        # System.halt()
        "undetermined"
    end
  end
end

File.stream!(file)
# |> Stream.take(10)
|> Stream.map(&LogCategorize.categorize(&1))
|> Enum.frequencies()
|> IO.inspect(IEx.inspect_opts())
