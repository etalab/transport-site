defmodule DB.Resource do
  @moduledoc """
  Resource model
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.{Dataset, LogsValidation, Repo, Validation}
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
    field(:conversion_latest_content_hash, :string)

    field(:is_community_resource, :boolean)

    # only relevant for community resources, name of the owner or the organization that published the resource
    field(:community_resource_publisher, :string)
    field(:description, :string)

    # some community resources have been generated from another dataset (like the generated NeTEx / GeoJson)
    field(:original_resource_url, :string)

    # Id of the datagouv resource. Note that several resources can have the same datagouv_id
    # because one datagouv resource can be a CSV linking to several transport.data.gouv's resources
    # (this is done for OpenDataSoft)
    field(:datagouv_id, :string)

    # we add 2 fields, that are already in the metadata json, in order to be able to add some indices
    field(:start_date, :date)
    field(:end_date, :date)

    field(:filesize, :integer)

    belongs_to(:dataset, Dataset)
    has_one(:validation, Validation, on_replace: :delete)
    has_many(:logs_validation, LogsValidation, on_replace: :delete, on_delete: :delete_all)
  end

  @spec endpoint() :: binary()
  def endpoint, do: Application.get_env(:transport, :gtfs_validator_url) <> "/validate"

  @doc """
  A validation is needed if the last update from the data is newer than the last validation.
  ## Examples

    iex> Resource.needs_validation(%Resource{format: "GTFS", content_hash: "a_sha",
    ...> validation: %Validation{validation_latest_content_hash: "a_sha"}}, false)
    {false, "content hash has not changed"}
    iex> Resource.needs_validation(%Resource{format: "GTFS", content_hash: "a_sha",
    ...> validation: %Validation{validation_latest_content_hash: "a_sha"}}, true)
    {true, "forced validation"}
    iex> Resource.needs_validation(%Resource{format: "gbfs", content_hash: "a_sha",
    ...> validation: %Validation{validation_latest_content_hash: "a_sha"}}, false)
    {false, "we validate only the GTFS"}
    iex> Resource.needs_validation(%Resource{format: "GTFS", content_hash: "a_sha"}, false)
    {true, "no previous validation"}
    iex> Resource.needs_validation(%Resource{format: "gtfs-rt", content_hash: "a_sha"}, true)
    {false, "we validate only the GTFS"}
    iex> Resource.needs_validation(%Resource{format: "GTFS", content_hash: "a_sha",
    ...> validation: %Validation{validation_latest_content_hash: "another_sha"}}, false)
    {true, "content hash has changed"}
  """
  @spec needs_validation(__MODULE__.t(), boolean()) :: {boolean(), binary()}
  def needs_validation(%__MODULE__{format: format}, _force_validation) when format != "GTFS" do
    # we only want to validate GTFS
    {false, "we validate only the GTFS"}
  end

  def needs_validation(%__MODULE__{}, true = _force_validation) do
    {true, "forced validation"}
  end

  def needs_validation(
        %__MODULE__{
          content_hash: content_hash,
          validation: %Validation{validation_latest_content_hash: validation_latest_content_hash}
        } = r,
        _force_validation
      ) do
    # if there is already a validation, we revalidate only if the file has changed
    if content_hash != validation_latest_content_hash do
      Logger.info("the files for resource #{r.id} have been modified since last validation, we need to revalidate them")
      {true, "content hash has changed"}
    else
      {false, "content hash has not changed"}
    end
  end

  def needs_validation(%__MODULE__{}, _force_validation) do
    # if there is no validation, we want to validate
    {true, "no previous validation"}
  end

  @spec validate_and_save(__MODULE__.t(), boolean()) :: {:error, any} | {:ok, nil}
  def validate_and_save(%__MODULE__{id: resource_id} = resource, force_validation) do
    Logger.info("Validating #{resource.url}")

    with {true, msg} <- __MODULE__.needs_validation(resource, force_validation),
         {:ok, validations} <- validate(resource),
         {:ok, _} <- save(resource, validations) do
      # log the validation success
      Repo.insert(%LogsValidation{
        resource_id: resource_id,
        timestamp: DateTime.truncate(DateTime.utc_now(), :second),
        is_success: true,
        skipped_reason: msg
      })

      {:ok, nil}
    else
      {false, skipped_reason} ->
        # the ressource does not need to be validated again, we have nothing to do
        Repo.insert(%LogsValidation{
          resource_id: resource_id,
          timestamp: DateTime.truncate(DateTime.utc_now(), :second),
          is_success: true,
          skipped: true,
          skipped_reason: skipped_reason
        })

        {:ok, nil}

      {:error, error} ->
        Logger.warn("Error when calling the validator: #{error}")

        Sentry.capture_message("unable_to_call_validator",
          extra: %{url: resource.url, error: error}
        )

        # log the validation error
        Repo.insert(%LogsValidation{
          resource_id: resource_id,
          timestamp: DateTime.truncate(DateTime.utc_now(), :second),
          is_success: false,
          error_msg: error
        })

        {:error, error}
    end
  rescue
    e ->
      Logger.error("error while validating resource #{resource.id}: #{inspect(e)}")

      Repo.insert(%LogsValidation{
        resource_id: resource_id,
        timestamp: DateTime.truncate(DateTime.utc_now(), :second),
        is_success: false,
        error_msg: "#{inspect(e)}"
      })

      {:error, e}
  end

  @spec validate(__MODULE__.t()) :: {:error, any} | {:ok, map()}
  def validate(%__MODULE__{url: nil}), do: {:error, "No url"}

  def validate(%__MODULE__{url: url, format: "GTFS"}) do
    case @client.get("#{endpoint()}?url=#{URI.encode_www_form(url)}", [], recv_timeout: @timeout) do
      {:ok, %@res{status_code: 200, body: body}} -> Jason.decode(body)
      {:ok, %@res{body: body}} -> {:error, body}
      {:error, %@err{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error in validation"}
    end
  end

  def validate(%__MODULE__{format: f, id: id}) do
    Logger.info("cannot validate resource id=#{id} because we don't know how to validate the #{f} format")
    {:ok, %{"validations" => nil, "metadata" => nil}}
  end

  @spec save(__MODULE__.t(), map()) :: {:ok, any()} | {:error, any()}
  def save(%__MODULE__{id: id, format: format} = r, %{
        "validations" => validations,
        "metadata" => metadata
      }) do
    # When the validator is unable to open the archive, it will return a fatal issue
    # And the metadata will be nil (as it couldn’t read them)
    if is_nil(metadata) and format == "GTFS",
      do: Logger.warn("Unable to validate resource ##{id}: #{inspect(validations)}")

    __MODULE__
    |> preload(:validation)
    |> Repo.get(id)
    |> change(
      metadata: metadata,
      validation: %Validation{
        date: DateTime.utc_now() |> DateTime.to_string(),
        details: validations,
        max_error: get_max_severity_error(validations),
        validation_latest_content_hash: r.content_hash
      },
      auto_tags: find_tags(r, metadata),
      start_date: str_to_date(metadata["start_date"]),
      end_date: str_to_date(metadata["end_date"])
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
        :datagouv_id,
        :last_update,
        :latest_url,
        :is_available,
        :auto_tags,
        :is_community_resource,
        :community_resource_publisher,
        :original_resource_url,
        :content_hash,
        :description,
        :filesize
      ]
    )
    |> validate_required([:url, :datagouv_id])
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
      "UnloadableModel" => dgettext("validations", "Not compliant with the GTFS specification"),
      "MissingMandatoryFile" => dgettext("validations", "Missing mandatory file"),
      "ExtraFile" => dgettext("validations", "Extra file"),
      "ImpossibleToInterpolateStopTimes" => dgettext("validations", "Impossible to interpolate stop times")
    }

  @spec has_metadata?(__MODULE__.t()) :: boolean()
  def has_metadata?(%__MODULE__{} = r), do: r.metadata != nil

  @spec valid?(__MODULE__.t()) :: boolean()
  def valid?(%__MODULE__{metadata: %{"start_date" => s, "end_date" => e}}) when not is_nil(s) and not is_nil(e),
    do: true

  def valid?(%__MODULE__{}), do: false

  @spec is_outdated?(__MODULE__.t()) :: boolean
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
        with %Validation{details: details} when details == %{} <- Repo.get_by(Validation, resource_id: id) do
          %{severity: "Irrevelant", count_errors: 0}
        else
          _ ->
            Logger.error("Unable to get validation of resource #{id}")
            nil
        end

      {:error, error} ->
        Logger.error(error)
        nil
    end
  end

  def get_max_severity_validation_number(_), do: nil

  @spec get_max_severity_error(any) :: binary()
  defp get_max_severity_error(%{} = validations) do
    validations
    |> Map.values()
    |> Enum.map(fn v -> hd(v)["severity"] end)
    |> Enum.min_by(fn sev -> Validation.severities(sev).level end, fn -> "NoError" end)
  end

  defp get_max_severity_error(_), do: nil

  @spec is_gtfs?(__MODULE__.t()) :: boolean()
  def is_gtfs?(%__MODULE__{format: "GTFS"}), do: true
  def is_gtfs?(_), do: false

  @spec is_gbfs?(__MODULE__.t()) :: boolean
  def is_gbfs?(%__MODULE__{format: "gbfs"}), do: true
  def is_gbfs?(_), do: false

  @spec is_netex?(__MODULE__.t()) :: boolean
  def is_netex?(%__MODULE__{format: "NeTEx"}), do: true
  def is_netex?(_), do: false

  @spec is_gtfs_rt?(__MODULE__.t()) :: boolean
  def is_gtfs_rt?(%__MODULE__{format: "gtfs-rt"}), do: true
  def is_gtfs_rt?(%__MODULE__{format: "gtfsrt"}), do: true
  def is_gtfs_rt?(_), do: false

  @spec is_siri_lite?(__MODULE__.t()) :: boolean
  def is_siri_lite?(%__MODULE__{format: "SIRI lite"}), do: true
  def is_siri_lite?(_), do: false

  @spec is_real_time?(__MODULE__.t()) :: boolean
  def is_real_time?(resource) do
    is_gtfs_rt?(resource) or is_gbfs?(resource) or is_siri_lite?(resource)
  end

  @spec other_resources_query(__MODULE__.t()) :: Ecto.Query.t()
  def other_resources_query(%__MODULE__{} = resource),
    do:
      from(r in __MODULE__,
        where: r.dataset_id == ^resource.dataset_id and r.id != ^resource.id and not is_nil(r.metadata)
      )

  @spec other_resources(__MODULE__.t()) :: [__MODULE__.t()]
  def other_resources(%__MODULE__{} = r), do: r |> other_resources_query() |> Repo.all()

  @spec str_to_date(binary()) :: Date.t() | nil
  defp str_to_date(date) when not is_nil(date) do
    date
    |> Date.from_iso8601()
    |> case do
      {:ok, v} ->
        v

      {:error, e} ->
        Logger.error("date '#{date}' not valid: #{inspect(e)}")
        nil
    end
  end

  defp str_to_date(_), do: nil
end
