defmodule Transport.GBFSMetadata do
  @moduledoc """
  Compute and store metadata for GBFS resources.
  """
  require Logger

  def compute_feed_metadata(%DB.Resource{url: url}), do: compute_feed_metadata(url)

  def compute_feed_metadata(url) when is_binary(url),
    do: Transport.Shared.GBFSMetadata.Wrapper.compute_feed_metadata(url)

  def validator_name, do: "GBFS-Validator"
end
