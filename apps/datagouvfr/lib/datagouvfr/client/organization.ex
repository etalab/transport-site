defmodule Datagouvfr.Client.Organization.Wrapper do

  @callback get(dataset_id :: binary()) :: {:ok, map()} | {:error, map()}

  defp impl, do: Application.get_env(:datagouvfr, :organization_impl)

  def get(id), do: impl().get(id)
end

defmodule Datagouvfr.Client.Organization.Mock do
  @moduledoc """
  A Mock Organization, for test configuration
  """
  @behaviour Datagouvfr.Client.Organization.Wrapper

  def get(_id) do
    {:ok, %{"members" => [%{"user" => %{"id" => "1"}}]}}
  end



end



defmodule Datagouvfr.Client.Organization do
  @moduledoc """
  Implementation of data.gouv.fr API for Organization, see doc: https://doc.data.gouv.fr/api/reference/#/organizations
  """
  @behaviour Datagouvfr.Client.Organization.Wrapper

  alias Datagouvfr.Client.API

  @endpoint "organizations"

   @doc """
  Call to GET /api/1/organizations/:id/
  """
  def get(id) do
    @endpoint
    |> Path.join(id)
    |> API.get()
  end
end
