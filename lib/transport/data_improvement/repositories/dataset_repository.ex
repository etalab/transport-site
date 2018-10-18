defmodule Transport.DataImprovement.DatasetRepository do
  @moduledoc """
  A dataset repository in the context of data improvement.
  """

  alias Transport.DataImprovement.Dataset
  use Transport.DataImprovement.Macros, :repository
  alias Transport.Datagouvfr.Client.Datasets, as: Repo # smell

  @entity_id :dataset_uuid

  # write API

  @spec update_file(%Dataset{}, %Plug.Conn{}) :: {atom(), map()} # smell
  def update_file(%Dataset{} = dataset, %Plug.Conn{} = conn) do
    Repo.upload_resource(
      conn,
      Map.get(dataset, @entity_id),
      Map.get(dataset, :file)
    )
  end
end
