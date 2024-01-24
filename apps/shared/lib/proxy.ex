defmodule Shared.Proxy do
  @moduledoc """
  Shared methods useful when proxying requests in our apps.
  """

  @doc """
  A list of HTTP headers that will be forwarded by our proxy.

  For now we use an allowlist we can gradually expand.
  Make sure to avoid including "hop-by-hop" headers here.
  https://book.hacktricks.xyz/pentesting-web/abusing-hop-by-hop-headers
  """
  def forwarded_headers_allowlist do
    [
      "content-type",
      "content-length",
      "date",
      "last-modified",
      "etag"
    ]
  end
end
