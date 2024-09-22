[file] = Path.wildcard("../*.log")

IO.inspect(file, IEx.inspect_opts())

defmodule LogCategorize do
  def categorize(line) do
    cond do
      String.contains?(line, "path=/gbfs") ->
        "/path/gbfs"

      String.contains?(line, "GET /gbfs") ->
        "GET /path/gbfs"

      String.contains?(line, "GET /resource/") or String.contains?(line, "HEAD /resource/") ->
        "proxy:resource:get"

      String.contains?(line, "Telemetry event: processing") and String.contains?(line, "proxy request") ->
        "telemetry:proxy"

      String.contains?(line, "Proxy response for") ->
        "proxy:response"

      String.contains?(line, "Processing proxy request for identifier") ->
        "proxy:processing"

      String.contains?(line, "Sent 200 in") ->
        "response:200"

      String.contains?(line, "Sent 404 in") ->
        "response:404"

      true ->
        # IO.write(line)
        # System.halt()
        "undetermined"
    end
  end
end

File.stream!(file)
|> Enum.reduce(%{}, fn line, acc ->
  category = LogCategorize.categorize(line)
  bytes = byte_size(line)
  Map.update(acc, category, bytes, &(&1 + bytes))
end)
|> IO.inspect(label: "Bytes per Category")
