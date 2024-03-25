#! /usr/bin/env mix run

#
# A script to have a summaried look at largish NeTEx, leveraging SAX parsing.
#
# ```
# mix run scripts/netex-accessibilite.exs | uniq -c | sed -e 's/ *//' -e 's/ /\t/'
# ```
#

# https://www.data.gouv.fr/fr/datasets/cheminements-pietons-dans-paris-dapres-openstreetmap/
url = "https://www.data.gouv.fr/fr/datasets/r/7cef040d-c211-4bef-a239-75afa5cd357b"

file = Path.join("cache-dir", "netex-accessibilite.xml")

if File.exists?(file) do
  IO.puts("File available at #{file}")
else
  IO.puts("Downloading #{url} to #{file}")
  %{status: 200} = Transport.HTTPClient.get!(url, into: File.stream!(file))
end

defmodule IndentedElementPrinterParser do
  @moduledoc """
  A simple SAX parser able to print only the XML elements, in indented fashion,
  with a notion of depth limit.

  TODO: given we show a large number of items, a summary similar to how `uniq` works in Linux would help,
  for now it is recommended to pipe into `uniq` (see top of the script).
  """

  @behaviour Saxy.Handler

  def handle_event(:start_element, {name, _attributes}, state) do
    {indent_level, state} = Keyword.get_and_update(state, :indent_level, fn i -> {i || 0, (i || 0) + 1} end)

    unless indent_level >= state[:max_level] do
      IO.puts(String.duplicate(" ", indent_level) <> "<" <> name <> ">")
    end

    {:ok, state}
  end

  def handle_event(:end_element, _, state) do
    {_indent_level, state} = Keyword.get_and_update(state, :indent_level, fn i -> {i, i - 1} end)
    {:ok, state}
  end

  def handle_event(_, _, state), do: {:ok, state}
end

file
|> File.stream!()
# NOTE: temporary work-around for https://github.com/qcam/saxy/issues/127
|> Stream.with_index()
|> Stream.map(fn {x, index} ->
  if index == 0, do: String.replace(x, " encoding='ASCII'", ""), else: x
end)
|> Saxy.parse_stream(IndentedElementPrinterParser, max_level: System.get_env("LEVEL", "5") |> String.to_integer())
