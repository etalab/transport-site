defmodule Transport.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  alias Transport.{Dataset, Repo}
  import Ecto.{Changeset, Query}
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
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30", type: "public-transit"}, validation_date: "2018-01-01"})
      true
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-01", type: "public-transit"}, validation_date: "2018-01-30"})
      false
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30", type: "public-transit"}})
      true
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30", type: "micro-mobility"}})
      false
  """
  def needs_validation(%__MODULE__{dataset: dataset, validation_date: validation_date}) do
    case [dataset.type, validation_date] do
      ["public-transit", nil] -> true
      ["public-transit", validation_date] -> dataset.last_update > validation_date
      _ -> false
    end
  end

  def validate_and_save(%__MODULE__{} = resource) do
    Logger.info("Validating #{resource.url}")
    with {:ok, validations} <- validate(resource),
      {:ok, _} <- save(resource, validations) do
        Logger.info("Ok!")
    else
      {:error, error} ->
         Logger.warn("Error when calling the validator: #{error}")
         Sentry.capture_message("unable_to_call_validator", extra: %{url: resource.url, error: error})
      _ -> Logger.warn("Unknown error")
    end
  end

  def validate(%__MODULE__{url: nil}), do: {:error, "No url"}
  def validate(%__MODULE__{url: url}) do
    case @client.get("#{@endpoint}?url=#{url}", [], recv_timeout: @timeout) do
      {:ok, %@res{status_code: 200, body: body}} -> Poison.decode(body)
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error"}
    end
  end

  def save(%{id: id}, %{"validations" => validations, "metadata" => metadata}) do
    # When the validator is unable to open the archive, it will return a fatal issue
    # And the metadata will be nil (as it couldn’t read the them)
    if is_nil(metadata) do
      Logger.warn("Unable to validate: #{id}")
      Sentry.capture_message("validation_failed", extra: %{id: id, validations: validations})
    end

    __MODULE__
    |> Repo.get(id)
    |> change(validation_date: DateTime.utc_now |> DateTime.to_string)
    |> change(validations: validations)
    |> change(metadata: metadata)
    |> Repo.update
  end

  def save(url, _) do
    Logger.warn("Unknown error when saving the validation")
    Sentry.capture_message("validation_save_failed", extra: url)
  end

  def changeset(resource, params) do
    resource
    |> cast(
      params,
      [:validations, :validation_date, :is_active, :url,
       :format, :last_import, :title, :metadata, :id
      ])
    |> validate_required([:url])
  end

  def issue_types, do: @issue_types

  def valid?(%__MODULE__{} = r), do: r.metadata != nil

  def validate_and_save_all(args \\ ["--all"]) do
    __MODULE__
    |> preload(:dataset)
    |> Repo.all()
    |> Enum.filter(fn r -> r.dataset.type == "public-transit" or r.dataset.type == "transport-statique" end)
    |> Enum.filter(&(List.first(args) == "--all" or needs_validation(&1)))
    |> Enum.each(&validate_and_save/1)
  end

end
