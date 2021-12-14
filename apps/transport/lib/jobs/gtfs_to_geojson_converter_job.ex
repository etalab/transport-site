defmodule Transport.GtfsToGeojsonConverterJob do
  @moduledoc """

  """
  use Oban.Worker, max_attempts: 1
  import Logger
  alias DB.{Repo, Resource}

  @impl true
  def perform(%Oban.Job{args: %{"bucket" => bucket, "uuid" => uuid}}) do

    :ok
  end
end
