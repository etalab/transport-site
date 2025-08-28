defmodule Transport.CachedFiles do
  @moduledoc """
  Reads various CSV and JSON files and caches them in memory.

  This module provides a centralized cache for static file contents that are
  frequently accessed throughout the application. Files are loaded once at
  startup and kept in memory for fast access.
  """
  use Agent

  def start_link(_params) do
    Agent.start_link(fn -> load_documents() end, name: __MODULE__)
  end

  @spec reusers :: [binary()]
  def reusers do
    Agent.get(__MODULE__, & &1.reusers)
  end

  @spec facilitators :: [binary()]
  def facilitators do
    Agent.get(__MODULE__, & &1.facilitators)
  end

  @spec zfe_ids :: [binary()]
  def zfe_ids do
    Agent.get(__MODULE__, & &1.zfe_ids)
  end

  @spec gbfs_operators :: [binary()]
  def gbfs_operators do
    Agent.get(__MODULE__, & &1.gbfs_operators)
  end

  @spec load_documents :: map()
  defp load_documents do
    %{
      reusers: read_csv("reusers.csv"),
      facilitators: read_csv("facilitators.csv"),
      zfe_ids: read_csv("zfe_ids.csv"),
      gbfs_operators: read_csv("gbfs_operators.csv")
    }
  end

  @spec read_csv(binary()) :: [[binary()]]
  defp read_csv(filename) do
    (Application.app_dir(:transport, "priv") <> "/#{filename}")
    |> File.stream!()
    |> CSV.decode(separator: ?;, headers: true, validate_row_length: true)
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {_, array} -> array end)
  end
end
