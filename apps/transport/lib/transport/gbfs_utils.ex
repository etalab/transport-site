defmodule Transport.GBFSUtils do
  @moduledoc """
  Useful functions for GBFS data
  """
  alias DB.Resource

  def gbfs_validation_link(%Resource{format: "gbfs", url: url}) do
    gbfs_validation_link(url)
  end

  def gbfs_validation_link(url) do
    :transport
    |> Application.fetch_env!(:gbfs_validator_website)
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{url: url}))
    |> URI.to_string()
  end
end
