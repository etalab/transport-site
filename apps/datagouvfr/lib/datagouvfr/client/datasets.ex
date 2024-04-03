defmodule Datagouvfr.Client.Datasets do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/datasets endpoints
  """

  import Datagouvfr.Gettext
  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.OAuth, as: OAuthClient
  require Logger
  alias Helpers

  use Vex.Struct
  alias __MODULE__

  @endpoint "datasets"

  defstruct description: nil,
            frequency: nil,
            licence: "ODbL",
            organization: nil,
            title: nil

  validates(:description,
    length: [
      min: 1,
      message: dgettext("dataset", "A description is needed")
    ]
  )

  validates(:frequency,
    inclusion: [
      "bimonthly",
      "fourTimesAWeek",
      "semidaily",
      "weekly",
      "threeTimesAWeek",
      "hourly",
      "monthly",
      "unknown",
      "semimonthly",
      "threeTimesAMonth",
      "quarterly",
      "triennial",
      "threeTimesADay",
      "punctual",
      "continuous",
      "quinquennial",
      "semiweekly",
      "biweekly",
      "threeTimesAYear",
      "irregular",
      "annual",
      "semiannual",
      "daily",
      "biennial",
      "fourTimesADay"
    ]
  )

  validates(:organization,
    length: [
      min: 1,
      message: dgettext("dataset", "An organization is needed")
    ]
  )

  validates(:title,
    length: [
      min: 1,
      message: dgettext("dataset", "A title is needed")
    ]
  )

  @spec new(map()) :: %__MODULE__{}
  def new(%{} = map) do
    map
    |> Map.take(keys())
    |> Enum.reduce(%Datasets{}, &accumulator_atomizer/2)
  end

  @spec get_id_from_url(String.t()) :: String.t() | nil
  def get_id_from_url(url) do
    case get_infos_from_url(url) do
      %{id: id} -> id
      _ -> nil
    end
  end

  @spec get_infos_from_url(String.t()) :: map() | nil
  def get_infos_from_url(url) do
    with filename when not is_nil(filename) <- Helpers.filename_from_url(url),
         {:ok, dataset} <- [@endpoint, filename] |> API.get() do
      %{id: dataset["id"], title: dataset["title"], organization: get_in(dataset, ["organization", "name"])}
    else
      _ -> nil
    end
  end

  @doc """
  Make a user follow a dataset
  """
  @spec post_followers(Plug.Conn.t(), String.t()) :: {atom, map}
  def post_followers(%Plug.Conn{} = conn, dataset_id) do
    OAuthClient.post(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Make a user unfollow a dataset
  """
  @spec delete_followers(Plug.Conn.t(), String.t()) :: {atom, map}
  def delete_followers(%Plug.Conn{} = conn, dataset_id) do
    OAuthClient.delete(
      conn,
      Path.join([@endpoint, dataset_id, "followers"])
    )
  end

  @doc """
  Fetch **only user IDs** following a dataset.
  """
  @spec get_followers(String.t()) :: {atom, map}
  def get_followers(dataset_id) do
    [@endpoint, dataset_id, "followers", "?page_size=500"]
    |> Path.join()
    |> API.get([{"x-fields", "data{follower{id}}, next_page"}])
  end

  @doc """
  Call to GET /api/1/datasets/:id/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/datasets/put_dataset
  """
  @spec get(String.t()) :: {atom, any}
  def get(id) do
    @endpoint
    |> Path.join(id)
    |> API.get()
  end

  @spec accumulator_atomizer({any(), any()}, map()) :: map()
  def accumulator_atomizer({key, value}, m) do
    Map.put(m, String.to_existing_atom(key), value)
  end

  @spec keys :: [binary()]
  defp keys do
    %Datasets{}
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
  end
end
