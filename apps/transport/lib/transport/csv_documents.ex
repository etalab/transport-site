defmodule Transport.CSVDocuments do
@moduledoc """
Reads the CSV file of all Real Time Providers and caches it
"""
  use Agent

  def start_link(_params) do
    Agent.start_link(fn -> load_documents() end, name: __MODULE__)
  end

  def real_time_providers do
    Agent.get(__MODULE__, & &1.real_time_providers)
  end

  defp load_documents do
    %{
      real_time_providers: read_csv("real_time_providers.csv")
    }
  end

  defp read_csv(filename) do
    Application.app_dir(:transport, "priv") <> "/#{filename}"
    |> File.stream!
    |> CSV.decode(separator: ?;, headers: true)
    |> Enum.filter(fn {:ok, _} -> true
    _ -> false
    end)
    |> Enum.map(fn {_, array} -> array end)
  end

end
