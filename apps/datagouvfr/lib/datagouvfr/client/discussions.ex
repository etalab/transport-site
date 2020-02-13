defmodule Datagouvfr.Client.Discussions do
  @moduledoc """
  An API client for data.gouv.fr discussions
  """

  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.OAuth, as: Client
  require Logger

  @endpoint "discussions"

  @doc """
  Call to post /api/1/discussions/:id/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/comment_discussion
  """
  @spec post(%Plug.Conn{}, binary(), binary()) :: Client.oauth2_response()
  def post(%Plug.Conn{} = conn, id_, comment) do
    Client.post(conn, Path.join(@endpoint, id_), %{comment: comment}, [])
  end

  @doc """
  Call to post /api/1/discussions/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/create_discussion
  """
  @spec post(binary(), binary(), binary(), boolean()) :: Client.oauth2_response()
  def post(id_, title, comment, blank) when is_binary(id_) do
    headers = [
      {"X-API-KEY", Application.get_env(:transport, :datagouvfr_apikey)}
    ]

    API.post(@endpoint, payload_post(id_, title, comment), headers, blank)
  end

  @spec post(%Plug.Conn{}, binary, binary, binary, nil | any) :: Client.oauth2_response()
  def post(%Plug.Conn{} = conn, id_, title, comment, extras \\ nil) do
    Client.post(conn, @endpoint, payload_post(id_, title, comment, extras), [])
  end

  @doc """
  Call to GET /api/1/discussions/
  """
  @spec get(binary()) :: map() | nil
  def get(id) do
    @endpoint
    |> API.get([], follow_redirect: true, params: %{for: id})
    |> case do
      {:ok, %{"data" => data}} ->
        data

      {:error, error} ->
        Logger.error("When fetching discussions for id #{id}: #{inspect(error)}")
        nil
    end
  end

  @spec payload_post(binary(), binary(), binary(), [] | nil) :: map()
  defp payload_post(id_, title, comment, extras \\ nil) do
    payload = %{
      comment: comment,
      title: title,
      subject: %{class: "Dataset", id: id_}
    }

    if is_nil(extras), do: payload, else: Map.put(payload, :extras, extras)
  end
end
