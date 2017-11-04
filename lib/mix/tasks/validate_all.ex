defmodule Mix.Tasks.ValidateData do
  @moduledoc """
  Queues all ok data to validation.
  """

  use Mix.Task
  alias Transport.DataValidator.Server

  @shortdoc "Queue ok valid data to validation phase"
  def run(_) do
    Server.start_link()
    get_json()
    |> case do
    {:ok, data} ->
      data
      |> Enum.filter(fn d -> Map.get(d, "download_uri") != nil end)
      |> Enum.filter(fn d -> Enum.empty?(d["anomalies"]) end)
      |> Enum.map(fn d -> queue(d["download_uri"]) end)
    end
  end

  defp queue(url) do
    Server.validate_data(url)
    IO.puts(url <> " queued")
  end

  defp get_json do
    with {:ok, body} <- File.read("priv/static/data/datasets.json"),
         {:ok, json} <- Poison.decode(body), do: {:ok, json}
  end
end
