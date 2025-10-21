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

  def static_irve_schema do
    Agent.get(__MODULE__, & &1.static_irve_schema)
  end

  def dynamic_irve_schema do
    Agent.get(__MODULE__, & &1.dynamic_irve_schema)
  end

  @spec load_documents :: map()
  defp load_documents do
    %{
      facilitators: read_csv("facilitators.csv"),
      zfe_ids: read_csv("zfe_ids.csv"),
      gbfs_operators: read_csv("gbfs_operators.csv"),
      static_irve_schema: read_json("schema-irve-statique.json"),
      dynamic_irve_schema: read_json("schema-irve-dynamique.json")
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

  @spec read_json(binary()) :: map()
  def read_json(filename) do
    __DIR__
    |> Path.join("../../../shared/meta/" <> filename)
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end
end
