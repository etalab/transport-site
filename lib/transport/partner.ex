defmodule Transport.Partner do
  @moduledoc """
  Partner model
  """
  use Ecto.Schema

  schema "partner" do
    field :page, :string
    field :datagouv_id, :string
    field :type, :string
    field :name, :string
  end

  alias Datagouvfr.Client
  require Logger

  def is_datagouv_partner_url?(url), do: Regex.match?(partner_regex(), url)

  def from_url(partner_url) when is_binary(partner_url) do
    partner_url
    |> get_type_and_slug()
    |> get_api_response()
    |> case do
      nil -> {:error, nil}
      api_response ->
        {:ok, %__MODULE__{
          page: api_response["page"],
          datagouv_id: api_response["id"],
          type: get_type(partner_url),
          name: get_name(api_response)
        }}
    end
  end

  def count_reuses(%__MODULE__{type: type, id: id}) do
    get_api_response(
      ["reuses", "?#{type}=#{id}"],
      fn json -> Enum.count(json["data"]) end,
      [{"X-Fields", "data{created_at}"}]
    )
  end

  def description(%__MODULE__{type: type, id: id}) do
    get_api_response(
      ["reuses", "?#{type}=#{id}"],
      fn json -> json["description"] end,
      [{"X-Fields", "description"}]
    )
  end

  # private functions

  defp get_name(%{"name" => name}), do: name
  defp get_name(%{"first_name" => f_n, "last_name" => l_n}), do: f_n <> " " <> l_n

  defp split_url(url) do
     url
     |> String.split("/")
     |> Enum.filter(&(String.length(&1) != 0))
  end

  defp get_type_and_slug(url), do: url |> split_url() |> Enum.take(-2)

  defp get_type(url), do: url |> split_url() |> Enum.at(-2)

  defp partner_regex do
    :datagouvfr
    |> Application.get_env(:site)
    |> Regex.escape()
    |> Kernel.<>(".*\/(organizations|users)\/(.*)\/$")
    |> Regex.compile!()
  end

  def get_api_response(url, process_response \\ &(&1), headers \\ [] ) do
    url_api = Client.process_url(url)

    with {:ok, %{status_code: 200, body: body}} <- HTTPoison.get(url_api, headers),
         {:ok, json} <- Poison.decode(body) do
      process_response.(json)
    else
      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error("Got status code #{status_code} when reaching #{url_api}")
        Logger.error(body)
        nil
      {:error, error} ->
        Logger.error("Error while reaching #{url_api}")
        Logger.error(error)
        nil
    end
  end
end
