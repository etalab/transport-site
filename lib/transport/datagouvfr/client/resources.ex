defmodule Transport.Datagouvfr.Client.Resources do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/datasets/resources endpoints
  """

  import TransportWeb.Gettext
  import Transport.Datagouvfr.Client, only: [put_request: 3, post_request: 4]
  use Vex.Struct
  alias __MODULE__

  @endpoint "datasets"

  defstruct [
    description: nil,
    title: nil,
    dataset: nil,
  ]

  validates :description, length: [
    min: 1,
    message: dgettext("dataset", "A description is needed")
  ]

  validates :title, length: [
    min: 1,
    message: dgettext("dataset", "A title is needed")
  ]

  @spec new(map()) :: %__MODULE__{}
  def new(%{} = map) do
    map
    |> Map.take(keys())
    |> Enum.reduce(%Resources{}, &accumulator_atomizer/2)
  end

  @doc """
  upload a resource to a dataset
  """
  @spec upload(%Plug.Conn{}, String.t, %Plug.Upload{}) :: {atom, map}
  def upload(%Plug.Conn{} = conn, dataset_id, file) do
    post_request(
      conn,
      Path.join([@endpoint, dataset_id, "upload"]),
      {"file", file},
      [{"content-type", "multipart/form-data"}]
    )
  end

  @doc """
  upload a community resource
  """
  @spec upload_community_resource(%Plug.Conn{}, map, String.t) :: {atom, map}
  def upload_community_resource(%Plug.Conn{} = conn, params, linked_dataset_id) do
    url = Path.join([@endpoint,
                    linked_dataset_id,
                    "upload",
                    "community"])
    post_request(conn,
                 url,
                 {"file", params["dataset"]},
                 [{"content-type", "multipart/form-data"}])
  end

  @doc """
    Make a PUT call to /datasets/{dataset}/resources/{rid}/
    You can use this to add details to a dataset such as its title, description,
    dataset id and organization
  """
  def put_community_resource(%Plug.Conn{} = conn, params, resource_id, dataset) do
    params
    |> Map.put("dataset", dataset)
    |> Resources.new()
    |> Vex.validate()
    |> case do
      {:ok, resource}  ->
        put_request(conn,
                    Path.join([@endpoint,
                               "community_resources",
                               resource_id]),
                    resource)
      {:error, errors} ->
        {:validation_error, errors}
    end
  end

  def accumulator_atomizer({key, value}, m) do
    Map.put(m, String.to_existing_atom(key), value)
  end

  defp keys do
    %Resources{}
    |> Map.from_struct
    |> Map.keys
    |> Enum.map(&Atom.to_string/1)
  end
end
