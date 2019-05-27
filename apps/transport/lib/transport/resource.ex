defmodule Transport.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  alias Transport.{Dataset, Repo, Validation}
  import Ecto.{Changeset, Query}
  import TransportWeb.Gettext
  require Logger

  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 60_000

  schema "resource" do
    field :is_active, :boolean
    field :url, :string
    field :format, :string
    field :last_import, :string
    field :title, :string
    field :metadata, :map
    field :last_update, :string
    field :latest_url, :string
    field :is_available, :boolean, default: true

    belongs_to :dataset, Dataset
    has_one :validation, Validation, on_replace: :delete
  end

  def endpoint, do: Application.get_env(:transport, :gtfs_validator_url) <> "/validate"

  @doc """
  A validation is needed if the last update from the data is newer than the last validation.
  ## Examples
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30", type: "public-transit"}, validation: %Validation{date: "2018-01-01"}})
      true
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-01", type: "public-transit"}, validation: %Validation{date: "2018-01-30"}})
      false
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30", type: "public-transit"}, validation: %Validation{}})
      true
      iex> Resource.needs_validation(%Resource{dataset: %{last_update: "2018-01-30", type: "micro-mobility"}, validation: %Validation{}})
      false
  """
  def needs_validation(%__MODULE__{dataset: dataset, validation: %Validation{date: validation_date}}) do
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
    case @client.get("#{endpoint()}?url=#{URI.encode_www_form(url)}", [], recv_timeout: @timeout) do
      {:ok, %@res{status_code: 200, body: body}} -> Poison.decode(body)
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error"}
    end
  end

  def save(%{id: id}, %{"validations" => validations, "metadata" => metadata}) do
    # When the validator is unable to open the archive, it will return a fatal issue
    # And the metadata will be nil (as it couldn’t read the them)
    if is_nil(metadata), do: Logger.warn("Unable to validate: #{id}")

    __MODULE__
    |> preload(:validation)
    |> Repo.get(id)
    |> change(
      metadata: metadata,
      validation: %Validation{
        date: DateTime.utc_now |> DateTime.to_string,
        details: validations
      }
    )
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
      [:is_active, :url, :format, :last_import, :title,
       :metadata, :id, :last_update, :latest_url, :is_available]
    )
    |> validate_required([:url])
  end

  def issues_short_translation, do: %{
    "UnusedStop" => dgettext("validations", "Unused stops"),
    "Slow" => dgettext("validations", "Slow"),
    "ExcessiveSpeed" => dgettext("validations", "Excessive speed between two stops"),
    "NegativeTravelTime" => dgettext("validations", "Negative travel time between two stops"),
    "CloseStops" => dgettext("validations", "Close stops"),
    "NullDuration" => dgettext("validations", "Null duration between two stops"),
    "InvalidReference" => dgettext("validations", "Invalid reference"),
    "InvalidArchive" => dgettext("validations", "Invalid archive"),
    "MissingRouteName" => dgettext("validations", "Missing route name"),
    "MissingId" => dgettext("validations", "Missing id"),
    "MissingCoordinates" => dgettext("validations", "Missing coordinates"),
    "InvalidCoordinates" => dgettext("validations", "Invalid coordinates"),
    "InvalidRouteType" => dgettext("validations", "Invalid route type"),
    "MissingUrl" => dgettext("validations", "Missing url"),
    "InvalidUrl" => dgettext("validations", "Invalid url"),
    "InvalidTimezone" => dgettext("validations", "Invalid timezone"),
    "DuplicateStops" => dgettext("validations", "Duplicate stops"),
    "MissingPrice" => dgettext("validations", "Missing price"),
    "InvalidCurrency" => dgettext("validations", "Invalid currency"),
    "InvalidTransfers" => dgettext("validations", "Invalid transfers"),
    "InvalidTransferDuration" => dgettext("validations", "Invalid transfer duration"),
    "MissingLanguage" => dgettext("validations", "Missing language"),
    "InvalidLanguage" => dgettext("validations", "Invalid language"),
    "DupplicateObjectId" => dgettext("validations", "Dupplicate object id"),
    "UnloadableModel" => dgettext("validations", "Unloadable model"),
    "MissingMandatoryFile" => dgettext("validations", "Missing mandatory file"),
    "ExtraFile" => dgettext("validations", "Extra file")
}

  def valid?(%__MODULE__{} = r), do: r.metadata != nil

  def validate_and_save_all(args \\ ["--all"]) do
    __MODULE__
    |> preload(:dataset)
    |> Repo.all()
    |> Enum.filter(fn r -> r.dataset.type == "public-transit" or r.dataset.type == "transport-statique" end)
    |> Enum.filter(&(List.first(args) == "--all" or needs_validation(&1)))
    |> Enum.each(&validate_and_save/1)
  end

  def get_expire_at(%Date{} = date), do: get_expire_at("#{date}")
  def get_expire_at(date) do
    __MODULE__
    |> where([r], fragment("metadata->>'end_date' = ?", ^date))
    |> preload([:dataset])
    |> Repo.all()
  end
end
