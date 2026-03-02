defmodule Datagouvfr.Client.Datasets do
  @moduledoc """
  A wrapper to get datasets from data.gouv.fr API (or mock it for tests)
  See https://doc.data.gouv.fr/api/reference/#/datasets
  """
  use Gettext, backend: TransportWeb.Gettext
  use Vex.Struct

  defstruct description: nil,
            frequency: nil,
            licence: "ODbL",
            organization: nil,
            title: nil

  @type t :: %__MODULE__{}

  validates(:description,
    length: [
      min: 1,
      message: dgettext("datagouv-dataset", "A description is needed")
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
      message: dgettext("datagouv-dataset", "An organization is needed")
    ]
  )

  validates(:title,
    length: [
      min: 1,
      message: dgettext("datagouv-dataset", "A title is needed")
    ]
  )

  @callback new(map()) :: %__MODULE__{}
  def new(map), do: impl().new(map)

  @callback get_id_from_url(String.t()) :: String.t() | nil
  def get_id_from_url(url), do: impl().get_id_from_url(url)

  @callback get_infos_from_url(String.t()) :: map() | nil
  def get_infos_from_url(url), do: impl().get_infos_from_url(url)

  @doc """
  Fetch **only user IDs** following a dataset.
  """
  @callback get_followers(String.t()) :: {atom, map}
  def get_followers(dataset_id), do: impl().get_followers(dataset_id)

  @doc """
  Call to GET /api/1/datasets/:id/
  You can see documentation here: https://doc.data.gouv.fr/api/reference/#/datasets/get_dataset
  """
  @callback get(String.t()) :: {atom, any}
  def get(id), do: impl().get(id)

  defp impl, do: Application.get_env(:transport, :datasets_impl)
end

defmodule Datagouvfr.Client.Datasets.External do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/datasets endpoints
  """

  alias Datagouvfr.Client.API
  require Logger
  alias Helpers

  @behaviour Datagouvfr.Client.Datasets

  @endpoint "datasets"

  @spec new(map()) :: Datagouvfr.Client.Datasets.t()
  def new(%{} = map) do
    map
    |> Map.take(keys())
    |> Enum.reduce(%Datagouvfr.Client.Datasets{}, &accumulator_atomizer/2)
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
  You can see documentation here: https://doc.data.gouv.fr/api/reference/#/datasets/get_dataset
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
    %Datagouvfr.Client.Datasets{}
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
  end
end
