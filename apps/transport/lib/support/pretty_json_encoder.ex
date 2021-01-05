defmodule TransportWeb.PrettyJSONEncoder do
  @moduledoc """
  An encoder that you can use to pretty-print the API JSON output
  for easier debugging. See https://stackoverflow.com/a/38278387/20302
  """

  def encode_to_iodata!(data) do
    Jason.encode_to_iodata!(data, pretty: true)
  end
end
