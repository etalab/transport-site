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

  def latest_comment_timestamp(nil), do: nil

  def latest_comment_timestamp(discussions) do
    case discussions do
      [] ->
        nil

      [d] ->
        discussion_timestamp(d)

      [d | other_discussions] ->
        latest_naive_datetime(
          discussion_timestamp(d),
          latest_comment_timestamp(other_discussions)
        )
    end
  end

  def comment_timestamp(comment) do
    comment
    |> Map.get("posted_on")
    |> NaiveDateTime.from_iso8601()
    |> case do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  def discussion_timestamp(discussion) do
    discussion
    |> Map.get("discussion")
    |> comments_latest_timestamp()
  end

  def comments_latest_timestamp(comments) do
    case comments do
      [] -> nil
      [comment] -> comment_timestamp(comment)
      [c | comments] -> latest_naive_datetime(comment_timestamp(c), comments_latest_timestamp(comments))
    end
  end

  def latest_naive_datetime(date1, date2) do
    case NaiveDateTime.compare(date1, date2) do
      :lt -> date2
      _ -> date1
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
