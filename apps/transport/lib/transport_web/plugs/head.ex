defmodule TransportWeb.Plugs.Head do
  @moduledoc """
  A Plug to convert `HEAD` requests to `GET` requests but it remembers that
  it was originally a `HEAD` request.

  A fork from the original [Plug.Head](https://hexdocs.pm/plug/Plug.Head.html)
  """
  @behaviour Plug

  @impl true
  def init([]), do: []

  @impl true
  def call(%Plug.Conn{method: "HEAD"} = conn, []) do
    %{conn | method: "GET"} |> Plug.Conn.assign(:original_method, "HEAD")
  end

  def call(conn, []), do: conn
end
