defmodule TransportWeb.PrettyJSONEncoder do
  # see https://stackoverflow.com/a/38278387/20302
  def encode_to_iodata!(data) do
    Jason.encode_to_iodata!(data, pretty: true)
  end
end
