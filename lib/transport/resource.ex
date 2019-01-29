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
  "CloseStops", "NullDuration", "InvalidReference", "InvalidArchive", "MissingRouteName",
  "MissingId", "MissingCoordinates", "InvalidCoordinates", "InvalidRouteType"]

  schema "resource" do
    field :validations, :map
    field :validation_date, :string
    field :is_active, :boolean
    field :url, :string
    field :format, :string
    field :last_import, :string
    field :title, :string
    field :metadata, :map

    belongs_to :dataset, Dataset
  end

  @doc """
  A validation is needed if the last update from the data is newer than the last validation.
  ## Examples
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30"}, validation_date: "2018-01-01"})
      true
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-01"}, validation_date: "2018-01-30"})
      false
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30"}})
      true
  """
  def needs_validation(%__MODULE__{dataset: dataset, validation_date: validation_date}) do
    dataset.last_update > validation_date
  end
  def needs_validation(_dataset), do: true

  def validate_and_save(%__MODULE__{} = resource) do
    Logger.info("Validating #{resource.url}")
    with {:ok, validations} <- validate(resource),
      {:ok, _} <- save(resource, validations) do
        Logger.info("Ok!")
    else
      {:error, error} -> Logger.warn("Error: #{error}")
      _ -> Logger.warn("Unknown error")
    end
  end

  def validate(%__MODULE__{url: url}) do
    case @client.get("#{@endpoint}?url=#{url}", [], recv_timeout: @timeout) do
      {:ok, %@res{status_code: 200, body: body}} -> Poison.decode(body)
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error"}
    end
  end

  def save(%{url: url}, %{"validations" => validations, "metadata" => metadata}) do
    __MODULE__
    |> Repo.get_by(url: url)
    |> change(validation_date: DateTime.utc_now |> DateTime.to_string)
    |> change(validations: validations)
    |> change(metadata: metadata)
    |> Repo.update
  end

  def changeset(resource, params) do
    cast(resource, params, [:validations, :validation_date, :is_active,
     :url, :format, :last_import, :title, :metadata])
  end

  def issue_types, do: @issue_types

  def valid?(%__MODULE__{} = r), do: r.metadata != nil

end
