defmodule Transport.RealTimeProviders do
@moduledoc """
Reads the CSV file of all Real Time Providers and caches it
"""
  use Agent

  def start_link(_params) do
    Agent.start_link(fn -> read_csv() end, name: __MODULE__)
  end

  def value do
    Agent.get(__MODULE__, & &1)
  end

  defp read_csv do
    Application.app_dir(:transport, "priv") <> "/real_time_providers.csv"
    |> File.stream!
    |> CSV.decode(separator: ?;, headers: true)
    |> Enum.filter(fn {:ok, _} -> true
    _ -> false
    end)
    |> Enum.map(fn {_, array} -> array end)
  end

end
