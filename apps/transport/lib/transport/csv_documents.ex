defmodule Transport.CSVDocuments do
  @moduledoc """
  Reads the CSV file of all Real Time Providers and caches it
  """
  use Agent

  def start_link(_params) do
    Agent.start_link(fn -> load_documents() end, name: __MODULE__)
  end

  @spec real_time_providers :: [binary()]
  def real_time_providers do
    Agent.get(__MODULE__, & &1.real_time_providers)
  end

  @spec reusers :: [binary()]
  def reusers do
    Agent.get(__MODULE__, & &1.reusers)
  end

  @spec load_documents :: map()
  defp load_documents do
    %{
      real_time_providers: read_csv("real_time_providers.csv"),
      reusers: read_csv("reusers.csv")
    }
  end

  @spec read_csv(binary()) :: [[binary()]]
  defp read_csv(filename) do
    (Application.app_dir(:transport, "priv") <> "/#{filename}")
    |> File.stream!()
    |> CSV.decode(separator: ?;, headers: true)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {_, array} -> array end)
  end
end
