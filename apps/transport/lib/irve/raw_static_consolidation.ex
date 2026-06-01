defmodule Transport.IRVE.RawStaticConsolidation do
  @moduledoc """
  To be deleted.
  """

  def ensure_producer_is_org!(%{dataset_organisation_id: "???"}), do: raise("producer is not an organization")

  def ensure_producer_is_org!(_row), do: :ok
end
