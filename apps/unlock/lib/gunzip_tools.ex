defmodule Unlock.GunzipTools do
  # Decompress (gzip only) if needed. More algorithms can be added later based on real-life testing
  # The Mint documentation contains useful bits to deal with more scenarios here
  # https://github.com/elixir-mint/mint/blob/main/pages/Decompression.md#decompressing-the-response-body
  #
  # Make sure to lowercase the headers first with `lowercase_headers` if your HTTP client does not do it already.
  def maybe_gunzip(body, headers) do
    is_gzipped? = get_header(headers, "content-encoding") == ["gzip"]

    if is_gzipped? do
      :zlib.gunzip(body)
    else
      body
    end
  end

  # Inspiration https://github.com/elixir-plug/plug/blob/v1.13.6/lib/plug/conn.ex#L615
  def get_header(headers, key) do
    for {^key, value} <- headers, do: value
  end

  def lowercase_headers(headers) do
    headers
    |> Enum.map(fn {h, v} -> {String.downcase(h), v} end)
  end
end
