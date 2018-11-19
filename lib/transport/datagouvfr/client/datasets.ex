defmodule Transport.Datagouvfr.Client.Datasets do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/datasets endpoints
  """

  import TransportWeb.Gettext
  import Transport.Datagouvfr.Client, only: [get_request: 2, put_request: 3,
                                             post_request: 3, post_request: 4,
                                             post_request: 2, delete_request: 2]
  require Logger

  use Vex.Struct
  alias __MODULE__

  @endpoint "datasets"

  defstruct [
    description: nil,
    frequency: nil,
    licence: "ODbL",
    organization: nil,
    title: nil
  ]

  validates :description, length: [
    min: 1,
    message: dgettext("dataset", "A description is needed")
  ]

  validates :frequency, inclusion: [
    "bimonthly", "fourTimesAWeek", "semidaily", "weekly",
    "threeTimesAWeek", "hourly", "monthly", "unknown",
    "semimonthly", "threeTimesAMonth", "quarterly",
    "triennial", "threeTimesADay", "punctual",
    "continuous", "quinquennial", "semiweekly",
    "biweekly", "threeTimesAYear", "irregular", "annual",
    "semiannual", "daily", "biennial", "fourTimesADay"
  ]

  validates :organization, length: [
    min: 1,
    message: dgettext("dataset", "An organization is needed")
  ]

  validates :title, length: [
    min: 1,
    message: dgettext("dataset", "A title is needed")
  ]

  @spec new(map()) :: %__MODULE__{}
  def new(%{} = map) do
    map
    |> Map.take(keys())
    |> Enum.reduce(%Datasets{}, &accumulator_atomizer/2)
  end

  @doc """
  Call to GET /api/1/organizations/:id/datasets/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/organizations/list_organization_datasets
  """
  @spec get(%Plug.Conn{}, map) :: {atom, [map]}
  def get(%Plug.Conn{} = conn, %{:organization => id}) do
    conn
    |> get_request(Path.join(["organizations", id, @endpoint]))
    |> case do #We need that for backward compatibility
      {:ok, %{"data" => data}} -> {:ok, data}
      {:ok, data} -> {:ok, data}
      {:error, error} ->
        Logger.error(error)
        {:error, error}
    end
  end

  @doc """
  Call to GET /api/1/datasets/:id/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/datasets/put_dataset
  """
  @spec get(%Plug.Conn{}, String.t) :: {atom, [map]}
  def get(%Plug.Conn{} = conn, id) do
    conn
    |> get_request(Path.join(@endpoint, id))
  end

  @doc """
  Call to PUT /api/1/datasets/:id/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/datasets/put_dataset
  """
  @spec put(%Plug.Conn{}, String.t, map) :: {atom, map}
  def put(%Plug.Conn{} = conn, id, dataset) when is_map(dataset) do
    conn
    |> put_request(Path.join(@endpoint, id), dataset)
  end

  @doc """
  Add a tag to a dataset
  """
  @spec put(%Plug.Conn{}, String.t, {:atom, String.t}) :: {atom, map}
  def put(%Plug.Conn{} = conn, id, {:add_tag, tag}) do
    conn
    |> get(id)
    |> case do
      {:ok, dataset} -> put(conn, id, add_tag(dataset, tag))
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Post a dataset
  """
  @spec post(%Plug.Conn{}, map)
    :: {atom, %Datasets{}} | {:error, atom} | {:validation_error, [String.t]}
  def post(%Plug.Conn{} = conn, %{} = params)
  do
    params
    |> Datasets.new()
    |> Vex.validate()
    |> case do
      {:ok, dataset}   -> post_request(conn, @endpoint, dataset)
      {:error, errors} -> {:validation_error, errors}
    end
  end

  @doc """
  upload a resource to a dataset
  """
  @spec upload_resource(%Plug.Conn{}, String.t, %Plug.Upload{}) :: {atom, map}
  def upload_resource(%Plug.Conn{} = conn, dataset_id, file) do
    post_request(
      conn,
      Path.join([@endpoint, dataset_id, "upload"]),
      {"file", file},
      [{"content-type", "multipart/form-data"}]
    )
  end

  @doc """
  Make a user follow a dataset
  """
  @spec post_followers(%Plug.Conn{}, String.t) :: {atom, map}
  def post_followers(%Plug.Conn{} = conn, dataset_id) do
    post_request(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Make a user unfollow a dataset
  """
  @spec delete_followers(%Plug.Conn{}, String.t) :: {atom, map}
  def delete_followers(%Plug.Conn{} = conn, dataset_id) do
    delete_request(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Get folowers of a dataset
  """
  @spec get_followers(%Plug.Conn{}, String.t) :: {atom, map}
  def get_followers(%Plug.Conn{} = conn, dataset_id) do
    get_request(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Is current_user subscribed to this dataset?
  """
  @spec current_user_subscribed?(%Plug.Conn{}, String.t) :: {atom, map}
  def current_user_subscribed?(%Plug.Conn{assigns: %{current_user: %{"id" => user_id}}} = conn, dataset_id) do
    conn
    |> get_followers(dataset_id)
    |> is_user_in_followers?(user_id, conn)
  end
  def current_user_subscribed?(_, _), do: false

  #private functions

  """
  Check if user_id is in followers, if it's not, check in next page if there's one
  """
  defp is_user_in_followers?({:ok, %{"data" => followers} = page}, user_id, conn) when is_list(followers) do
    Enum.any?(followers,
      &(&1["follower"]["id"] == user_id)
    ) or is_user_in_followers?(page['next_page'], user_id, conn)
  end
  defp is_user_in_followers?(page_url, user_id, conn) when is_binary(page_url) do
    conn
    |> get_request(page_url)
    |> is_user_in_followers?(user_id, conn)
  end
  defp is_user_in_followers?(_, _, _), do: false

  @spec add_tag(map, String.t) :: map
  defp add_tag(dataset, tag) when is_map(dataset) do
    Map.put(dataset, "tags", [tag | dataset["tags"]])
  end

  def accumulator_atomizer({key, value}, m) do
    Map.put(m, String.to_existing_atom(key), value)
  end

  defp keys do
    %Datasets{}
    |> Map.from_struct
    |> Map.keys
    |> Enum.map(&Atom.to_string/1)
  end
end
