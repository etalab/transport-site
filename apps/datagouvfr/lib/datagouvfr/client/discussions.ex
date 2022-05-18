defmodule Datagouvfr.Client.Discussions.Wrapper do
  @moduledoc """
  A behavior for discussions
  """
  @callback get(binary()) :: []

  defp impl, do: Application.fetch_env!(:datagouvfr, :datagouvfr_discussions)

  def get(id), do: impl().get(id)
end

defmodule Datagouvfr.Client.Discussions.Dummy do
  @moduledoc """
  Dummy Discussions, outputing nil
  """
  @behaviour Datagouvfr.Client.Discussions.Wrapper

  @impl true
  def get(_), do: []
end

defmodule Datagouvfr.Client.Discussions do
  @moduledoc """
  An API client for data.gouv.fr discussions
  """
  @behaviour Datagouvfr.Client.Discussions.Wrapper

  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.OAuth, as: Client
  require Logger

  @endpoint "discussions"

  @doc """
  Call to post /api/1/discussions/:id/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/comment_discussion
  """
  @spec post(Plug.Conn.t(), binary(), binary()) :: Client.oauth2_response()
  def post(%Plug.Conn{} = conn, id_, comment) do
    Client.post(conn, Path.join(@endpoint, id_), %{comment: comment}, [])
  end

  @doc """
  Call to post /api/1/discussions/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/create_discussion
  """
  @spec post(binary(), binary(), binary(), boolean()) :: Client.oauth2_response()
  def post(id_, title, comment, blank) when is_binary(id_) do
    headers = [API.api_key_headers()]

    API.post(@endpoint, payload_post(id_, title, comment), headers, blank)
  end

  @spec post(Plug.Conn.t(), binary, binary, binary, nil | any) :: Client.oauth2_response()
  def post(%Plug.Conn{} = conn, id_, title, comment, extras \\ nil) do
    Client.post(conn, @endpoint, payload_post(id_, title, comment, extras), [])
  end

  @doc """
  Call to GET /api/1/discussions/
  """
  @impl true
  def get(id) do
    @endpoint
    |> API.get([], follow_redirect: true, params: %{for: id})
    |> case do
      {:ok, %{"data" => data}} ->
        data

      {:error, error} ->
        Logger.error("When fetching discussions for id #{id}: #{inspect(error)}")
        []
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
