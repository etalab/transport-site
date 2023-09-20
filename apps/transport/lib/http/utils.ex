defmodule Transport.Http.Utils do
  @moduledoc """
  Useful functions to work with http requests
  """
  require Logger

  def location_header(headers), do: header_value(headers, "location")

  def header_value(headers, header) do
    for {key, value} <- headers, String.downcase(key) == String.downcase(header) do
      value
    end
  end

  @doc """
  Takes a response body and response headers and try to convert the body to UTF-8.
  It looks at the charset defined in the `content-type` header.

  Inspired by https://bernheisel.com/blog/httpoison-and-decompression
  """
  def reencode_body_to_utf8(body, headers) do
    headers
    |> header_value("content-type")
    |> parse_charset()
    |> reencode_body(body)
  end

  defp parse_charset([content_type]), do: parse_charset(content_type)

  # Parse the content-type charset part and attempt to convert it to one of the two encodings we
  # support at the moment (`:utf8` and `:latin1`), expressed as atoms expected by the Erlang-unicode module
  # (see https://www.erlang.org/doc/man/unicode#type-encoding).
  # 
  # Keep the original value if no match is found.
  defp parse_charset(content_type) when is_binary(content_type) do
    case Plug.Conn.Utils.content_type(content_type) do
      {:ok, _, _, %{"charset" => charset}} ->
        # Case insensitive and ignore dashes
        cond do
          charset =~ ~r/utf-?8/i -> :utf8
          charset =~ ~r/iso-?8859-?1/i -> :latin1
          true -> charset
        end

      _ ->
        nil
    end
  end

  defp parse_charset(_), do: nil

  # When the header isn't sent, the RFC spec says we should assume ISO-8859-1, but the default is
  # actually different per format, eg, XML should be assumed UTF-8. We're going to not re-encode
  # if it's not sent and assume UTF-8. This should be safe for most cases.
  defp reencode_body(nil, body), do: body
  defp reencode_body(:utf8, body), do: body

  defp reencode_body(:latin1, body) do
    case :unicode.characters_to_binary(body, :latin1, :utf8) do
      {:error, binary, rest} ->
        Logger.error("Failed to re-encode text. BODY: #{inspect(binary)} REST: #{inspect(rest)}")
        body

      {:incomplete, reencoded_text, rest} ->
        Logger.warning("Failed to re-encode entire text. Dropping characters: #{inspect(rest)}")
        reencoded_text

      reencoded_text ->
        reencoded_text
    end
  end

  defp reencode_body(other, body) do
    Logger.error("Need to implement re-encoding support for: #{other}")
    body
  end
end
