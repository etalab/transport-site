defmodule Datagouvfr.Client.Datasets do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/datasets endpoints
  """

  import TransportWeb.Gettext
  alias Datagouvfr.Client
  require Logger
  alias Transport.Helpers

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
  @spec get(map) :: {atom, [map]}
  def get(%{:organization => id}) do
    ["organizations", id, @endpoint]
    |> Path.join()
    |> Client.get()
    |> case do #We need that for backward compatibility
      {:ok, %{"data" => data}} -> {:ok, data}
      {:ok, data} -> {:ok, data}
      {:error, error} ->
        Logger.error(error)
        {:error, error}
    end
  end

  @doc """
  Call to url
  """
  @spec get(keyword) :: {atom, [map]}
  def get([url: url]) do
    url
    |> Helpers.filename_from_url()
    |> Client.get()
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
  @spec get(String.t) :: {atom, [map]}
  def get(id) do
    @endpoint
    |> Path.join(id)
    |> Client.get()
  end

  @spec get_id_from_url(String.t) :: String.t
  def get_id_from_url(url) do
    case Client.get(url) do
      {:ok, dataset} -> dataset["id"]
      {:error, error} ->
        Logger.error(error)
        nil
    end
  end

  @doc """
  Make a user follow a dataset
  """
  @spec post_followers(%Plug.Conn{}, String.t) :: {atom, map}
  def post_followers(%Plug.Conn{} = conn, dataset_id) do
    Client.post(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Make a user unfollow a dataset
  """
  @spec delete_followers(%Plug.Conn{}, String.t) :: {atom, map}
  def delete_followers(%Plug.Conn{} = conn, dataset_id) do
    Client.delete(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Get folowers of a dataset
  """
  @spec get_followers(String.t) :: {atom, map}
  def get_followers(dataset_id) do
    [@endpoint, dataset_id, "followers"]
    |> Path.join()
    |> Client.get()
  end

  @doc """
  Is current_user subscribed to this dataset?
  """
  @spec current_user_subscribed?(%Plug.Conn{}, String.t) :: boolean
  def current_user_subscribed?(%Plug.Conn{assigns: %{current_user: %{"id" => user_id}}} = conn, dataset_id) do
    dataset_id
    |> get_followers()
    |> is_user_in_followers?(user_id, conn)
  end
  def current_user_subscribed?(_, _), do: false

  def is_active?(%{datagouv_id: id}) do
    path = Path.join([@endpoint, id])
    response =
      path
      |> Client.process_url()
      |> HTTPoison.head()

    not match?({:ok, %HTTPoison.Response{status_code: 404}}, response)
  end

  #private functions

  # Check if user_id is in followers, if it's not, check in next page if there's one
  defp is_user_in_followers?({:ok, %{"data" => followers} = page}, user_id, conn) when is_list(followers) do
    Enum.any?(followers,
      &(&1["follower"]["id"] == user_id)
    ) or is_user_in_followers?(page['next_page'], user_id, conn)
  end
  defp is_user_in_followers?(page_url, user_id, conn) when is_binary(page_url) do
    conn
    |> Client.get(page_url)
    |> is_user_in_followers?(user_id, conn)
  end
  defp is_user_in_followers?(_, _, _), do: false

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
