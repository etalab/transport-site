defmodule Mix.Tasks.Decode.GtfsRt do
  @shortdoc "Decode a GTFS-RT using the Elixir tooling"

  @moduledoc """
  A simple task to download a GTFS-RT feed, parse it (as protobuf) and dump it on screen as Elixir structures.
  """

  require Logger
  use Mix.Task

  def run([url]) do
    {:ok, _} = Application.ensure_all_started(:finch)
    {:ok, _} = Finch.start_link(name: GtfsRt.Finch)
    {:ok, %{status: 200, body: body}} = Finch.build(:get, url) |> Finch.request(GtfsRt.Finch)
    TransitRealtime.FeedMessage.decode(body) |> IO.inspect(IEx.inspect_opts())
  end
end
