defmodule Transport.Shared.ResourceSchema do
  @moduledoc """
  Guess schema names and versions for resources
  """
  import Helpers, only: [filename_from_url: 1]

  @spec guess_name(map(), binary()) :: binary() | nil
  @doc """
  Guess a schema name for a resource.

  ## Examples

    iex> guess_name(%{}, "public-transit")
    nil

    iex> guess_name(%{"format" => "json"}, "public-transit")
    nil

    iex> guess_name(%{"format" => "JSON", "url" => "https://example.com/zfe_zone_nom.json"}, "low-emission-zones")
    "etalab/schema-zfe"

    iex> guess_name(%{"format" => "json", "url" => "https://example.com/nope.zip"}, "low-emission-zones")
    nil

    iex> guess_name(%{"schema" => %{"name" => "etalab/schema-zfe"}}, "low-emission-zones")
    "etalab/schema-zfe"
  """

  def guess_name(%{"schema" => %{"name" => schema}}, _dataset_type) do
    schema
  end

  def guess_name(%{"url" => url, "format" => format}, "low-emission-zones") do
    appropriate_format = Enum.member?(["json", "geojson"], String.downcase(format))
    appropriate_filename = url |> filename_from_url() |> String.starts_with?("zfe")
    if appropriate_format and appropriate_filename, do: "etalab/schema-zfe"
  end

  def guess_name(_, _), do: nil

  @spec guess_version(map()) :: binary() | nil
  @doc """
  Guess a schema version for a resource.

  ## Examples

    iex> guess_version(%{"schema" => %{"version" => "1.1"}})
    "1.1"

    iex> guess_version(%{})
    nil
  """
  def guess_version(%{"schema" => %{"version" => version}}) do
    version
  end

  def guess_version(_), do: nil
end
