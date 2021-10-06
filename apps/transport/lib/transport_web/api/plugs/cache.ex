defmodule TransportWeb.API.Plugs.PublicCache do
  @moduledoc """
  A cache to set `cache-control` HTTP headers for responses suitable
  to be cached by browsers or caches.

  Default value: `max-age=60, public, must-revalidate`.

  Allowed options:
  - `max_age` (integer)
  """
  import Plug.Conn, only: [put_resp_header: 3]

  def init(options) do
    max_age = Keyword.get(options, :max_age, 60)

    unless is_integer(max_age) and max_age > 0 do
      raise ArgumentError, "max_age must be a positive integer, received #{inspect(max_age)}"
    end

    [{:max_age, max_age}]
  end

  def call(conn, options) do
    max_age = Keyword.fetch!(options, :max_age)
    conn |> put_resp_header("cache-control", "max-age=#{max_age}, public, must-revalidate")
  end
end
