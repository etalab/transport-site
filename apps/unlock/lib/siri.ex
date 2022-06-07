defmodule Unlock.SIRI do
  @doc """
  iex> Unlock.SIRI.parse_incoming("<elem attr='value'>text</elem>")
  {"elem", [{"attr", "value"}], ["text"]}
  """
  def parse_incoming(body) do
    {:ok, parsed_request} = Saxy.SimpleForm.parse_string(body, cdata_as_characters: false)
    parsed_request
  end
end
