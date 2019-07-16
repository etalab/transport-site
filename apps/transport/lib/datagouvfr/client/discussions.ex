defmodule Datagouvfr.Client.Discussions do
  @moduledoc """
  An API client for data.gouv.fr discussions
  """

  alias Datagouvfr.Client.HTTPoison, as: HTTPoisonClient
  alias Datagouvfr.Client.OAuth, as: Client
  require Logger

  @endpoint "discussions"

  @doc """
  Call to post /api/1/discussions/:id/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/comment_discussion
  """
  @spec post(%Plug.Conn{}, binary(), binary()) :: Client.oauth_response
  def post(%Plug.Conn{} = conn, id_, comment) do
    Client.post(conn, Path.join(@endpoint, id_), %{comment: comment}, [])
  end

  @doc """
  Call to post /api/1/discussions/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/create_discussion
  """
  @spec post(binary(), binary(), binary(), boolean()) :: Client.response
  def post(id_, title, comment, blank) when is_binary(id_) do
    headers = [
      {"X-API-KEY", Application.get_env(:transport, :datagouvfr_apikey)}
    ]
    HTTPoisonClient.post(@endpoint, payload_post(id_, title, comment), headers, blank)
  end
  @spec post(%Plug.Conn{}, binary, binary, binary, nil | any) :: Client.oauth_response
  def post(%Plug.Conn{} = conn, id_, title, comment, extras \\ nil) do
    Client.post(conn, @endpoint, payload_post(id_, title, comment, extras), [])
  end

  @doc """
  Call to GET /api/1/discussions/
  """
  def get(conn, id) do
    conn
    |> Client.get("/#{@endpoint}?for=#{id}", [], follow_redirect: true)
    |> case do
      {:ok, %{"data" => data}} -> data
      {:error, %OAuth2.Response{body: body}} ->
        Logger.error("When fetching discussions for id #{id}: #{body}")
        nil
      {:error, %OAuth2.Error{reason: reason}} ->
        Logger.error("When fetching discussions for id #{id}: #{reason}")
        nil
    end
  end

  defp payload_post(id_, title, comment, extras \\ nil) do
    payload = %{
      comment: comment,
      title: title,
      subject: %{class: "Dataset", id: id_},
    }

    if is_nil(extras) do payload else Map.put(payload, :extras, extras) end
  end
end
