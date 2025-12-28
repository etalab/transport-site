defmodule Datagouvfr.Client.Discussions.Wrapper do
  @moduledoc """
  A behavior for discussions
  """
  alias Datagouvfr.Client.OAuth

  @callback get(binary()) :: []
  def get(id), do: impl().get(id)

  @callback post(Plug.Conn.t(), binary(), binary(), close: boolean()) :: OAuth.oauth2_response()
  def post(%Plug.Conn{} = conn, discussion_id, comment, close: close),
    do: impl().post(conn, discussion_id, comment, close: close)

  @callback post(Plug.Conn.t(), binary(), binary(), binary()) :: OAuth.oauth2_response()
  def post(%Plug.Conn{} = conn, dataset_id, title, comment), do: impl().post(conn, dataset_id, title, comment)

  defp impl, do: Application.fetch_env!(:transport, :datagouvfr_discussions)
end

defmodule Datagouvfr.Client.Discussions.Dummy do
  @moduledoc """
  Dummy Discussions, outputing nil
  """
  @behaviour Datagouvfr.Client.Discussions.Wrapper

  @impl true
  def get(_), do: []

  @impl true
  def post(%Plug.Conn{}, _, _, close: _), do: {:ok, nil}

  @impl true
  def post(%Plug.Conn{}, _, _, _), do: {:ok, nil}
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
  Comment a discussion.

  POST to /api/1/discussions/:id/
  Documentation: https://doc.data.gouv.fr/api/reference/#/discussions/comment_discussion
  """
  @spec post(Plug.Conn.t(), binary(), binary()) :: Client.oauth2_response()
  def post(%Plug.Conn{} = conn, discussion_id, comment) do
    post(conn, discussion_id, comment, close: false)
  end

  @spec post(Plug.Conn.t(), binary(), binary(), close: boolean()) :: Client.oauth2_response()
  @impl true
  def post(%Plug.Conn{} = conn, discussion_id, comment, close: close) do
    Client.post(conn, Path.join(@endpoint, discussion_id), %{comment: comment, close: close}, [])
  end

  @doc """
  Create a new discussion.

  POST to /api/1/discussions/
  Documentation: https://doc.data.gouv.fr/api/reference/#/discussions/create_discussion
  """
  @spec post(Plug.Conn.t(), binary, binary, binary) :: Client.oauth2_response()
  @impl true
  def post(%Plug.Conn{} = conn, dataset_id, title, comment) when is_binary(comment) do
    payload = %{
      comment: comment,
      title: title,
      subject: %{class: "Dataset", id: dataset_id}
    }

    Client.post(conn, @endpoint, payload, [])
  end

  @doc """
  List discussions for a specific model.

  GET to /api/1/discussions/
  Documentation: https://doc.data.gouv.fr/api/reference/#/discussions/list_discussions
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
end
