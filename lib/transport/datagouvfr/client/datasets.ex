defmodule Transport.Datagouvfr.Client.Datasets do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/datasets endpoints
  """

  import Transport.Datagouvfr.Client, only: [get_request: 2, put_request: 3]

  @endpoint "datasets"

  @doc """
  Call to GET /api/1/organizations/:slug/datasets/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/organizations/list_organization_datasets
  """
  @spec get(%Plug.Conn{}, map) :: {atom, [map]}
  def get(%Plug.Conn{} = conn, %{:organization => slug}) do
    conn
    |> get_request(Path.join(["organizations", slug, @endpoint]))
  end

  @doc """
  Call to GET /api/1/datasets/:slug/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/datasets/put_dataset
  """
  @spec get(%Plug.Conn{}, String.t) :: {atom, [map]}
  def get(%Plug.Conn{} = conn, slug) do
    conn
    |> get_request(Path.join(@endpoint, slug))
  end

  @doc """
  Call to PUT /api/1/datasets/:slug/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/datasets/put_dataset
  """
  @spec put(%Plug.Conn{}, String.t, map) :: {atom, map}
  def put(%Plug.Conn{} = conn, slug, dataset) when is_map(dataset) do
    conn
    |> put_request(Path.join(@endpoint, slug), dataset)
  end

  @doc """
  Add a tag to a dataset
  """
  @spec put(%Plug.Conn{}, String.t, {:atom, String.t}) :: {atom, map}
  def put(%Plug.Conn{} = conn, slug, {:add_tag, tag}) do
    conn
    |> get(slug)
    |> case do
      {:ok, dataset} -> put(conn, slug, add_tag(dataset, tag))
      {:error, error} -> {:error, error}
    end
  end

  #private functions

  @spec add_tag(map, String.t) :: map
  defp add_tag(dataset, tag) when is_map(dataset) do
    Map.put(dataset, "tags", [tag | dataset["tags"]])
  end
end
