defmodule Datagouvfr.Client.Organization.Wrapper do
  @moduledoc """
  A Wrapper to get Organization from data.gouv.fr API (or mock it for tests)
  """
  @callback get(binary(), keyword()) :: {:ok, map()} | {:error, map()}
  @callback get(binary()) :: {:ok, map()} | {:error, map()}
  def get(id, opts), do: impl().get(id, opts)
  def get(id), do: impl().get(id)

  defp impl, do: Application.get_env(:transport, :organization_impl)
end

defmodule Datagouvfr.Client.Organization do
  @moduledoc """
  Implementation of data.gouv.fr API for Organization, see doc: https://doc.data.gouv.fr/api/reference/#/organizations
  """
  @behaviour Datagouvfr.Client.Organization.Wrapper
  @endpoint "organizations"
  alias Datagouvfr.Client.API

  @doc """
  Call to GET /api/1/organizations/:id/
  """
  @impl true
  def get(id, opts \\ []) do
    opts = Keyword.validate!(opts, restrict_fields: false)
    headers = if opts[:restrict_fields], do: [{"x-fields", "{logo_thumbnail,members{user{id}}}"}], else: []

    @endpoint
    |> Path.join(id)
    |> API.get(headers)
  end
end
