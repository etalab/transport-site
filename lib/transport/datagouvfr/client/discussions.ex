defmodule Transport.Datagouvfr.Client.Discussions do
  @moduledoc """
  An API client for data.gouv.fr discussions
  """

  import Transport.Datagouvfr.Client, only: [post_request: 3]

  @endpoint "discussions"

  @doc """
  Call to post /api/1/discussions/:id/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/comment_discussion
  """
  @spec post(%Plug.Conn{}, String.t, String.t) :: {atom, [map]}
  def post(%Plug.Conn{} = conn, id_, comment) do
    conn
    |> post_request(Path.join(@endpoint, id_), %{comment: comment})
  end

  @doc """
  Call to post /api/1/discussions/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/discussions/create_discussion
  """
  @spec post(%Plug.Conn{}, String.t, String.t, String.t, map) :: {atom, [map]}
  def post(%Plug.Conn{} = conn, id_, title, comment, extras \\ nil) do
    conn
    |> post_request(@endpoint,
                    %{comment: comment, title: title, extras: extras,
                      subject: %{class: "Dataset", id: id_}})
  end
end
