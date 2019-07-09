defmodule Datagouvfr.Client.Discussions do
  @moduledoc """
  An API client for data.gouv.fr discussions
  """

  alias Datagouvfr.Client
  require Logger

  @endpoint "discussions"

  @doc """
  Call to post /api/1/discussions/:id/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/comment_discussion
  """
  def post(%Plug.Conn{} = conn, id_, comment) do
    conn
    |> Client.post(Path.join(@endpoint, id_), %{comment: comment})
  end

  @doc """
  Call to post /api/1/discussions/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/create_discussion
  """
  def post(%Plug.Conn{} = conn, id_, title, comment, extras \\ nil) do
    payload = %{
      comment: comment,
      title: title,
      subject: %{class: "Dataset", id: id_},
    }

    payload = if is_nil(extras) do payload else Map.put(payload, :extras, extras) end

    Client.post(conn, @endpoint, payload)
  end

  @doc """
  Call to GET /api/1/discussions/
  """
  def get(conn, id) do
    conn
    |> Client.get("/#{@endpoint}?for=#{id}", [], follow_redirect: true)
    |> case do
      {:ok, %{"data" => data}} -> data
      {:error, %{reason: reason}} ->
        Logger.error("When fetching discussions for id #{id}: #{reason}")
        nil
      {:error, %{body: body}} ->
        Logger.error("When fetching discussions for id #{id}: #{body}")
        nil
    end
  end
end
