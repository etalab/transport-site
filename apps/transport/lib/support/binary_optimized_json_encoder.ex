defmodule TransportWeb.BinaryOptimizedJSONEncoder do
  @moduledoc """
  Some of the JSON payloads the app sends are costly to compute, so we're
  caching them. It is many times (x100) more efficient to store them as
  an Elixir binary (full string) rather than as detailed Elixir maps, due to
  both marshalling/unmarshalling costs from ETS, and re-encoding to JSON strings.

  Here we leverage Phoenix "format encoders" to override the "encoding to JSON"
  process: if the the data is already a binary, we assume it is encoded JSON already,
  and just pass it through.

  A caveat is that this assumes the app never sends back a single string of JSON,
  something that must be double-checked! If this becomes a problem, then it will be
  better to just use `send_resp` at specific places (see second link below).

  References:
  * https://hexdocs.pm/phoenix/1.5.8/Phoenix.Template.html#module-format-encoders
  * https://github.com/phoenixframework/phoenix/blob/38b3702fd468fea7075cdf996c19c22350fe1eec/lib/phoenix/controller.ex#L271-L286

  Credit goes to Benjamin Milde on Elixir lang slack channel
  for his help on this.
  """

  def encode_to_iodata!(data) when is_binary(data) do
    data
  end

  def encode_to_iodata!(data) do
    Phoenix.json_library().encode_to_iodata!(data)
  end
end
