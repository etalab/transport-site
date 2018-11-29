defmodule Transport.Partners.Partner do
  @moduledoc """
  Partner model
  """
  use Ecto.Schema

  schema "partner" do
    field :page, :string
    field :api_uri, :string
    field :name, :string
  end

  alias Transport.Datagouvfr.Client
  require Logger

  def is_datagouv_partner_url?(url), do: Regex.match?(partner_regex(), url)

  def from_url(partner_url) when is_binary(partner_url) do
    case get_api_response(partner_url) do
      {:ok, api_response} ->
        {:ok, %__MODULE__{
          page: api_response[:page],
          api_uri: api_response[:api_uri],
          name: api_response[:name]
        }}
      _ -> {:error, nil}
    end
  end

  # private functions

  defp get_name(%{"name" => name}), do: name
  defp get_name(%{"first_name" => f_n, "last_name" => l_n}), do: f_n <> " " <> l_n

  defp get_type_and_slug(url) do
     url
     |> String.split("/")
     |> Enum.filter(&(String.length(&1) != 0))
     |> Enum.take(-2)
  end

  defp get_api_response(url) do
    with [type, slug_or_id] <- get_type_and_slug(url),
         url_api <- Client.process_url([type, slug_or_id]),
         {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(url_api),
         {:ok, json} <- Poison.decode(body),
         json_with_name <- Map.put(json, :name, get_name(json)) do
      {:ok, json_with_name}
    else
      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error("Got status code #{status_code} when reaching #{url}")
        Logger.error(body)
        {:error, :bad_status_code}
      {:error, error} ->
        Logger.error("Error while reaching #{url}")
        Logger.error(error)
        {:error, error}
    end
  end

  defp partner_regex do
    :transport
    |> Application.get_env(:datagouvfr_site)
    |> Regex.escape()
    |> Kernel.<>(".*\/(organizations|users)\/(.*)\/$")
    |> Regex.compile!()
  end
end
