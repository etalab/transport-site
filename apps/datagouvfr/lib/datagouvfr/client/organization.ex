defmodule Datagouvfr.Client.Organization.Wrapper do
  @moduledoc """
  A Wrapper to get Organization from data.gouv.fr API (or mock it for tests)
  """
  @callback get(binary(), keyword()) :: {:ok, map()} | {:error, map()}

  defp impl, do: Application.get_env(:datagouvfr, :organization_impl)
  def get(id, opts), do: impl().get(id, opts)

  def get(id), do: impl().get(id)

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
  def get(id, opts \\ []) do
    args = if opts[:restrict_fields], do: [{"x-fields", "{logo_thumbnail,members{user{id}}}"}], else: []

    @endpoint
    |> Path.join(id)
    |> API.get(args)
  end
end
