defmodule Transport.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  alias Transport.{Dataset, Repo}
  import Ecto.Changeset
  require Logger

  @endpoint Application.get_env(:transport, :gtfs_validator_url) <> "/validate"
  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 60_000
  @issue_types ["UnusedStop", "Slow", "ExcessiveSpeed", "NegativeTravelTime",
  "CloseStops", "NullDuration", "InvalidReference", "InvalidArchive"]

  schema "resource" do
    field :validations, :map
    field :validation_date, :string
    field :is_active, :boolean
    field :url, :string
    field :format, :string
    field :last_import, :string
    field :title, :string

    belongs_to :dataset, Dataset
  end

  @doc """
  A validation is needed if the last update from the data is newer than the last validation.
  ## Examples
      iex> Resource.needs_validation(%Dataset{last_update: "2018-01-30", validation_date: "2018-01-01"})
      true
      iex> Resource.needs_validation(%Dataset{last_update: "2018-01-01", validation_date: "2018-01-30"})
      false
      iex> Resource.needs_validation(%Dataset{last_update: "2018-01-30"})
      true
  """
  def needs_validation(%__MODULE__{dataset: dataset, validation_date: validation_date}) do
    dataset.last_update > validation_date
  end
  def nedds_validation(_dataset), do: true

  def validate_and_save(%__MODULE__{} = resource) do
    Logger.info("Validating " <> resource.url)
    resource
    |> validate
    |> group_validations
    |> save_validations
    |> case do
      {:ok, _} -> Logger.info("Ok!")
      {:error, error} -> Logger.warn("Error: " <> error)
      _ -> Logger.warn("Unknown error")
    end
  end

  def validate(%__MODULE__{url: url}) do
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
      iex> Resource.group_validations(nil)
      nil
      iex> Resource.group_validations({:error, "moo"})
      {:error, "moo"}
      iex> v = %{"validations" => [%{"issue_type" => "Error"}]}
      iex> Resource.group_validations({:ok, %{url: "http", validations: v}})
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

  def save_validations({:ok, %{url: url, validations: validations}}) do
    Resource
    |> Repo.get_by(:url, url)
    |> change(validation_date: DateTime.utc_now |> DateTime.to_string)
    |> change(validations: validations)
    |> Repo.update
  end
  def save_validations({:error, error}), do: {:error, error}
  def save_validations(error), do: {:error, error}

  def changeset(resource, params) do
    cast(resource, params, [:validations, :validation_date, :is_active,
     :url, :format, :last_import, :title])
  end

  def issue_types, do: @issue_types

end
