defmodule Transport.Api.Base.Datagouvfr do
  @moduledoc """
  An API Base for data.gouv.fr
  """
  use HTTPoison.Base

  @base_url "DATAGOUVFR_SITE" |> System.get_env() || "udata.site" |> Path.join("/api/1/")

  def organizations!() do
    organizations!("")
  end

  def organizations!(q) do
    get!("organizations", [], params: %{q: q}).body[:data]
  end

  def process_url(url) do
    @base_url
    |> Path.join(url)
    |> URI.parse
    |> add_trailing_slash
  end

  def process_response_body(body) do
    body
    |> Poison.decode!
    |> Enum.map(fn({k, v}) -> {String.to_atom(k), v} end)
  end

  defp add_trailing_slash(uri) when is_map(uri) do
    %URI{uri | path: add_trailing_slash(uri.path)}
    |> to_string
  end

  defp add_trailing_slash(path) do
    case path |> String.slice(-1..-1) do
      "/" -> path
      _ -> path <> "/"
      end
  end
end
