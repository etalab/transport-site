defmodule Transport.Shared.ConditionalJSONEncoder do
  require Logger

  @moduledoc """
  Some of the JSON payloads the app sends are costly to compute, so we're
  caching them. It is many times (x100) more efficient to store them as
  an Elixir binary (full string) rather than as detailed Elixir maps, due to
  both marshalling/unmarshalling costs from ETS, and re-encoding to JSON strings.

  Here we leverage Phoenix "format encoders" to override the "encoding to JSON"
  process: if the data is a well-specified tuple indicating that the code calling
  `render` knows that the payload is already JSON encoded, we'll just pass the data
  through.

  We are using a tuple rather than just detecting that the data is binary because
  there could be places where the reply is just a string (e.g. "OK"), and this would
  require JSON encoding.

  This bit of code makes sure we can rely on `render` (common code path) instead of
  moving to `send_resp` calls to mimic `render` for JSON, so it is a bit more future-proof.

  References:
  * https://hexdocs.pm/phoenix/1.5.8/Phoenix.Template.html#module-format-encoders
  * https://github.com/phoenixframework/phoenix/blob/38b3702fd468fea7075cdf996c19c22350fe1eec/lib/phoenix/controller.ex#L271-L286

  Credit goes to Benjamin Milde on Elixir lang slack channel
  for his help on this.
  """

  def encode_to_iodata!({:skip_json_encoding, data}) when is_binary(data) do
    Logger.info("Skipping JSON encode step (payload is already JSON encoded)")
    data
  end

  def encode_to_iodata!(data) do
    Phoenix.json_library().encode_to_iodata!(data)
  end
end
