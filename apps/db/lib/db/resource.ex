defmodule DB.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, Repo, Validation}
  import Ecto.{Changeset, Query}
  import DB.Gettext
  require Logger

  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 180_000

  typed_schema "resource" do
    field(:is_active, :boolean)
    # real url
    field(:url, :string)
    field(:format, :string)
    field(:last_import, :string)
    field(:title, :string)
    field(:metadata, :map)
    field(:last_update, :string)
    # stable data.gouv.fr url if exists, else (for ODS gtfs as csv) it's the real url
    field(:latest_url, :string)
    field(:is_available, :boolean, default: true)
    field(:content_hash, :string)
    # automatically discovered tags
    field(:auto_tags, {:array, :string}, default: [])

    belongs_to(:dataset, Dataset)
    has_one(:validation, Validation, on_replace: :delete)
  end

  @spec endpoint() :: binary()
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
  @spec needs_validation(__MODULE__.t()) :: boolean()
  def needs_validation(%__MODULE__{dataset: dataset, validation: %Validation{date: validation_date}}) do
    case [dataset.type == "public-transit", validation_date] do
      [true, nil] -> true
      [true, validation_date] -> dataset.last_update > validation_date
      _ -> false
    end
  end

  @spec validate_and_save(__MODULE__.t()) :: {:error, any} | {:ok, nil}
  def validate_and_save(%__MODULE__{} = resource) do
    Logger.info("Validating #{resource.url}")

    with {:ok, validations} <- validate(resource),
         {:ok, _} <- save(resource, validations) do
      {:ok, nil}
    else
      {:error, error} ->
        Logger.warn("Error when calling the validator: #{error}")
        Sentry.capture_message("unable_to_call_validator", extra: %{url: resource.url, error: error})
        {:error, error}
    end
  end

  @spec validate(__MODULE__.t()) :: {:error, any} | {:ok, map()}
  def validate(%__MODULE__{url: nil}), do: {:error, "No url"}

  def validate(%__MODULE__{url: url}) do
    case @client.get("#{endpoint()}?url=#{URI.encode_www_form(url)}", [], recv_timeout: @timeout) do
      {:ok, %@res{status_code: 200, body: body}} -> Poison.decode(body)
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error"}
    end
  end

  @spec save(__MODULE__.t(), map()) :: {:ok, any()} | {:error, any()}
  def save(%__MODULE__{id: id, url: url} = r, %{"validations" => validations, "metadata" => metadata}) do
    # When the validator is unable to open the archive, it will return a fatal issue
    # And the metadata will be nil (as it couldn’t read them)
    if is_nil(metadata), do: Logger.warn("Unable to validate: #{id}")

    __MODULE__
    |> preload(:validation)
    |> Repo.get(id)
    |> change(
      metadata: metadata,
      validation: %Validation{
        date: DateTime.utc_now() |> DateTime.to_string(),
        details: validations
      },
      auto_tags: find_tags(r, metadata),
      content_hash: Hasher.get_content_hash(url)
    )
    |> Repo.update()
  end

  def save(url, _) do
    Logger.warn("Unknown error when saving the validation")
    Sentry.capture_message("validation_save_failed", extra: url)
  end

  # for the moment the tag detection is very simple, we only add the modes
  @spec find_tags(__MODULE__.t(), map()) :: [binary()]
  def find_tags(%__MODULE__{} = _r, %{"modes" => modes}) do
    modes
  end

  def find_tags(%__MODULE__{} = _r, _) do
    []
  end

  def changeset(resource, params) do
    resource
    |> cast(
      params,
      [
        :is_active,
        :url,
        :format,
        :last_import,
        :title,
        :metadata,
        :id,
        :last_update,
        :latest_url,
        :is_available,
        :auto_tags
      ]
    )
    |> validate_required([:url])
  end

  @spec issues_short_translation() :: %{binary() => binary()}
  def issues_short_translation,
    do: %{
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
      "MissingName" => dgettext("validations", "Missing name"),
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

  @spec valid?(__MODULE__.t()) :: boolean()
  def valid?(%__MODULE__{} = r), do: r.metadata != nil

  @spec validate_and_save_all([binary()]) :: :ok
  def validate_and_save_all(args \\ ["--all"]) do
    __MODULE__
    |> preload(:dataset)
    |> Repo.all()
    |> Enum.filter(fn r -> r.dataset.type == "public-transit" end)
    |> Enum.filter(&(List.first(args) == "--all" or needs_validation(&1)))
    |> Enum.each(&validate_and_save/1)
  end

  @spec is_outdated?(__MODULE__) :: boolean
  def is_outdated?(%__MODULE__{metadata: %{"end_date" => nil}}), do: false

  def is_outdated?(%__MODULE__{metadata: %{"end_date" => end_date}}),
    do: end_date <= Date.utc_today() |> Date.to_iso8601()

  def is_outdated?(_), do: true

  @spec get_max_severity_validation_number(__MODULE__) :: map() | nil
  def get_max_severity_validation_number(%__MODULE__{id: id}) do
    """
      SELECT json_data.value#>'{0,severity}', json_array_length(json_data.value)
      FROM validations, json_each(validations.details) json_data
      WHERE validations.resource_id = $1
    """
    |> Repo.query([id])
    |> case do
      {:ok, %{rows: rows}} when rows != [] ->
        [max_severity | _] =
          Enum.min_by(
            rows,
            fn [severity | _] -> Validation.severities(severity)[:level] end,
            fn -> nil end
          )

        count_errors =
          rows
          |> Enum.filter(fn [severity, _] -> severity == max_severity end)
          |> Enum.reduce(0, fn [_, nb], acc -> acc + nb end)

        %{severity: max_severity, count_errors: count_errors}

      {:ok, _} ->
        if Repo.get_by(Validation, resource_id: id).details == %{} do
          %{severity: "Irrevelant", count_errors: 0}
        else
          Logger.error("Unable to get validation of resource #{id}")
          nil
        end

      {:error, error} ->
        Logger.error(error)
        nil
    end
  end

  def get_max_severity_validation_number(_), do: nil

  @spec is_gtfs?(__MODULE__.t()) :: boolean()
  def is_gtfs?(%__MODULE__{format: "GTFS"}), do: true
  def is_gtfs?(%__MODULE__{metadata: m} = r) when not is_nil(m), do: not is_netex?(r)
  def is_gtfs?(_), do: false

  @spec is_gbfs?(__MODULE__.t()) :: boolean
  def is_gbfs?(%__MODULE__{format: "gbfs"}), do: true
  def is_gbfs?(_), do: false

  @spec is_netex?(__MODULE__.t()) :: boolean
  def is_netex?(%__MODULE__{format: "netex"}), do: true
  def is_netex?(_), do: false

  @spec other_resources_query(__MODULE__.t()) :: Ecto.Query.t()
  def other_resources_query(%__MODULE__{} = resource),
    do:
      from(r in __MODULE__,
        where: r.dataset_id == ^resource.dataset_id and r.id != ^resource.id and not is_nil(r.metadata)
      )

  @spec other_resources(__MODULE__.t()) :: [__MODULE__.t()]
  def other_resources(%__MODULE__{} = r), do: r |> other_resources_query() |> Repo.all()
end
