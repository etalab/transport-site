defmodule TransportWeb.Plugs.PutLocale do
  @moduledoc """
  Set the locale according to: the `locale` query param, the session, the `accept-language` HTTP header.
  """
  import Plug.Conn
  @supported_locales ["fr", "en"]
  @default_locale ["fr"]

  def init(options), do: options

  def call(conn, _opts) do
    locale = conn.params["locale"] || get_session(conn, :locale) || preferred_accept_language(conn)

    if locale in @supported_locales do
      Gettext.put_locale(locale)
      conn |> put_session(:locale, locale)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "Locale is not supported.")
      |> halt()
    end
  end

  def supported_locales, do: @supported_locales

  @doc """
  Determines the locale to use using the `accept-language` HTTP header.
  Fallbacks to the default locale if required.

  iex> preferred_accept_language(%Plug.Conn{req_headers: [{"accept-language", "fr-CH, fr;q=0.9, en;q=0.8, de;q=0.7, *;q=0.5"}]})
  "fr"
  iex> preferred_accept_language(%Plug.Conn{req_headers: []})
  "fr"
  iex> preferred_accept_language(%Plug.Conn{req_headers: [{"accept-language", "ru;q=0.9, *;q=0.5"}]})
  "fr"
  iex> preferred_accept_language(%Plug.Conn{req_headers: [{"accept-language", "en-CA;q=0.9, *;q=0.5"}]})
  "en"
  """
  def preferred_accept_language(conn) do
    conn
    |> extract_accept_language()
    |> Enum.filter(&(&1 in @supported_locales))
    |> Kernel.++(@default_locale)
    |> hd()
  end

  @doc """
  Parses the `accept-language` HTTP header.
  Inspired by https://github.com/smeevil/set_locale/blob/9b3b496b47a69c1174c2a324a458790d2b30dc97/lib/headers.ex#L1

  iex> extract_accept_language(%Plug.Conn{req_headers: [{"accept-language", "fr-CH, fr;q=0.9, en;q=0.8, de;q=0.7, *;q=0.5"}]})
  ["fr-CH", "fr", "en", "de"]
  iex> extract_accept_language(%Plug.Conn{req_headers: []})
  []
  iex> extract_accept_language(%Plug.Conn{req_headers: [{"accept-language", "*"}]})
  []
  iex> extract_accept_language(%Plug.Conn{req_headers: [{"accept-language", "fr-CH"}]})
  ["fr-CH", "fr"]
  iex> extract_accept_language(%Plug.Conn{req_headers: [{"accept-language", "en"}]})
  ["en"]
  """
  def extract_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [value | _] ->
        value
        |> String.split(",")
        |> Enum.map(&parse_language_option/1)
        |> Enum.sort(&(&1.quality > &2.quality))
        |> Enum.map(& &1.tag)
        |> Enum.reject(&is_nil/1)
        |> ensure_language_fallbacks()

      _ ->
        []
    end
  end

  defp parse_language_option(string) do
    captures = Regex.named_captures(~r/^\s?(?<tag>[\w\-]+)(?:;q=(?<quality>[\d\.]+))?$/i, string)

    quality =
      case Float.parse(captures["quality"] || "1.0") do
        {val, _} -> val
        _ -> 1.0
      end

    %{tag: captures["tag"], quality: quality}
  end

  defp ensure_language_fallbacks(tags) do
    Enum.flat_map(tags, fn tag ->
      [language | _] = String.split(tag, "-")
      if Enum.member?(tags, language), do: [tag], else: [tag, language]
    end)
  end
end
