defmodule Transport.Dataset do
  @moduledoc """
  Dataset schema
  """
  alias Transport.{AOM, Region, Repo}
  import Ecto.{Changeset, Query}
  import TransportWeb.Gettext
  require Logger
  use Ecto.Schema

  @endpoint Application.get_env(:transport, :gtfs_validator_url) <> "/validate"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 60_000

  schema "dataset" do
    field :coordinates, {:array, :float}
    field :datagouv_id, :string
    field :spatial, :string
    field :created_at, :string
    field :description, :string
    field :download_url, :string
    field :format, :string
    field :frequency, :string
    field :last_update, :string
    field :last_import, :string
    field :licence, :string
    field :logo, :string
    field :full_logo, :string
    field :slug, :string
    field :tags, {:array, :string}
    field :task_id, :string
    field :title, :string
    field :type, :string
    field :metadata, :map
    field :validations, :map
    field :validation_date, :string

    belongs_to :region, Region
    belongs_to :aom, AOM
  end
  use ExConstructor

  def search_datasets(search_string) do
    q = "%#{search_string}%"

    __MODULE__
    |> join(:left, [d], aom in AOM, on: d.aom_id == aom.id)
    |> join(:left, [d], region in Region, on: d.region_id == region.id)
    |> where([d, a, r],
      ilike(a.insee_commune_principale, ^q)
      or ilike(r.nom, ^q)
      or ilike(d.description, ^q)
      or ilike(d.title, ^q)
      or ilike(d.spatial, ^q)
    )
  end
  def search_datasets(search_string, []), do: search_datasets(search_string)
  def search_datasets(search_string, s), do: search_string |> search_datasets() |> select(^s)

  def list_datasets, do: from d in __MODULE__
  def list_datasets(%{} = params) do
    filters =
      params
      |> Map.take([:insee_commune_principale, :region, :type])
      |> Map.to_list
      |> Keyword.new

     list_datasets()
     |> where([d], ^filters)
  end
  def list_datasets(s) when is_list(s), do: list_datasets() |> select(^s)
  def list_datasets(filters, s) when is_list(s), do: filters |> list_datasets() |> select(^s)

  def changeset(dataset, params) do
    dataset
    |> cast(params, [:insee_commune_principale, :coordinates, :datagouv_id, :region,
      :spatial, :created_at, :description, :download_url, :format, :frequency, :last_update,
      :last_import, :licence, :logo, :full_logo, :slug, :tags, :task_id, :title, :type,
      :metadata, :validations, :validation_date])
  end

  @doc """
  A validation is needed if the last update from the data is newer than the last validation.
  ## Examples
      iex> Dataset.needs_validation(%Dataset{last_update: "2018-01-30", validation_date: "2018-01-01"})
      true
      iex> Dataset.needs_validation(%Dataset{last_update: "2018-01-01", validation_date: "2018-01-30"})
      false
      iex> Dataset.needs_validation(%Dataset{last_update: "2018-01-30"})
      true
  """
  def needs_validation(%__MODULE__{last_update: last_update, validation_date: validation_date}) do
    last_update > validation_date
  end
  def nedds_validation(_dataset), do: true

  def validate_and_save(%__MODULE__{} = dataset) do
    Logger.info("Validating " <> dataset.download_url)
    dataset
    |> validate
    |> group_validations
    |> add_metadata
    |> save_validations
    |> case do
      {:ok, _} -> Logger.info("Ok!")
      {:error, error} -> Logger.warn("Error: " <> error)
      _ -> Logger.warn("Unknown error")
    end
  end

  def validate(%__MODULE__{download_url: url}) do
    with {:ok, %@res{status_code: 200, body: body}} <-
           @client.get(@endpoint <> "?url=#{url}", [], timeout: @timeout, recv_timeout: @timeout),
         {:ok, validations} <- Poison.decode(body) do
      {:ok, %{url: url, validations: validations}}
    else
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      {:error, error} -> {:error, error}
      _ -> {:error, "Unknown error"}
    end
  end

  @doc """
  A validation is needed if the last update from the data is newer than the last validation.
  ## Examples
      iex> Dataset.group_validations(nil)
      nil
      iex> Dataset.group_validations({:error, "moo"})
      {:error, "moo"}
      iex> v = %{"validations" => [%{"issue_type" => "Error"}]}
      iex> Dataset.group_validations({:ok, %{url: "http", validations: v}})
      {:ok, %{url: "http", validations: %{"Error" => %{count: 1, issues: [%{"issue_type" => "Error"}]}}}}
  """
  def group_validations({:ok, %{url: url, validations: validations}}) do
    grouped_validations =
    validations
    |> Map.get("validations", [])
    |> Enum.group_by(fn validation -> validation["issue_type"] end)
    |> Map.new(fn {type, issues} -> {type, %{issues: issues, count: Enum.count issues}} end)

    {:ok, %{url: url, validations: grouped_validations}}
  end
  def group_validations(error), do: error

  def add_metadata({:ok, %{url: url, validations: validations}}) do
    {:ok,
    %{
      url: url,
      validations: Map.put(validations, "validation_date", DateTime.utc_now |> DateTime.to_string)
      }
    }
  end
  def add_metadata(error), do: error

  def save_validations({:ok, %{url: url, validations: validations}}) do
    Dataset
    |> Repo.get_by(:download_url, url)
    |> change(validations: validations)
    |> Repo.update
  end
  def save_validations({:error, error}), do: {:error, error}
  def save_validations(error), do: {:error, error}

  @doc """
  Builds a licence.
  ## Examples
      iex> %Dataset{licence: "fr-lo"}
      ...> |> Dataset.localise_licence
      "Open Licence"
      iex> %Dataset{licence: "Libertarian"}
      ...> |> Dataset.localise_licence
      "Not specified"
  """
  @spec localise_licence(%__MODULE__{}) :: String.t
  def localise_licence(%__MODULE__{licence: licence}) do
    case licence do
      "fr-lo" -> dgettext("reusable_data", "fr-lo")
      "odc-odbl" -> dgettext("reusable_data", "odc-odbl")
      "other-open" -> dgettext("reusable_data", "other-open")
      _ -> dgettext("reusable_data", "notspecified")
    end
end

end
