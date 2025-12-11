defmodule Transport.Validators.NeTEx.Validator do
  @moduledoc """
  Validator for NeTEx files calling enRoute Chouette Valid API. This is blocking
  (by polling the tier API) and can take quite some time upon completion.
  """

  require Logger
  alias Transport.Jobs.NeTExPollerJob, as: Poller
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_0, as: ResultsAdapter

  @behaviour Transport.Validators.Validator

  # 180 * 20 seconds = 1 hour
  @max_attempts 180

  defmacro too_many_attempts(attempt) do
    quote do
      unquote(attempt) > unquote(@max_attempts)
    end
  end

  @doc """
  Poll interval to play nice with the tier.

  iex> 0..9 |> Enum.map(&poll_interval(&1))
  [10, 10, 10, 10, 10, 10, 20, 20, 20, 20]
  """
  def poll_interval(nb_tries) when nb_tries < 6, do: 10
  def poll_interval(_), do: 20

  @impl Transport.Validators.Validator
  def validator_name, do: "enroute-chouette-netex-validator"

  # This will change with an actual versioning of the validator
  def validator_version, do: "0.2.0"

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{} = resource_history) do
    Logger.info("Validating NeTEx #{resource_history.id} with enRoute Chouette Valid")

    with_resource_file(resource_history, &validate_resource_history(resource_history, &1))
  end

  def validate_resource_history(resource_history, filepath) do
    validate_with_enroute(filepath)
    |> handle_validation_results(resource_history.id, &enqueue_poller(resource_history.id, &1))
  end

  def enqueue_poller(resource_history_id, validation_id, attempt \\ 0) do
    {:ok, _job} =
      Poller.new(%{"validation_id" => validation_id, "resource_history_id" => resource_history_id})
      |> Oban.insert(schedule_in: _seconds = poll_interval(attempt))

    :ok
  end

  def handle_validation_results(validation_results, resource_history_id, on_pending) do
    case validation_results do
      {:ok, %{url: result_url, elapsed_seconds: elapsed_seconds, retries: retries}} ->
        insert_validation_results(
          resource_history_id,
          result_url,
          %{elapsed_seconds: elapsed_seconds, retries: retries}
        )

        :ok

      {:error, %{details: {result_url, errors}, elapsed_seconds: elapsed_seconds, retries: retries}} ->
        insert_validation_results(
          resource_history_id,
          result_url,
          %{elapsed_seconds: elapsed_seconds, retries: retries},
          errors
        )

        :ok

      {:error, :unexpected_validation_status} ->
        Logger.error("Invalid API call to enRoute Chouette Valid (resource_history_id: #{resource_history_id})")

        :ok

      {:error, %{message: :timeout, retries: _retries}} ->
        Logger.error(
          "Timeout while fetching results on enRoute Chouette Valid (resource_history_id: #{resource_history_id})"
        )

        :ok

      {:pending, validation_id} ->
        on_pending.(validation_id)
    end
  end

  @type error_details :: %{:message => String.t(), optional(:retries) => integer()}

  @type validation_id :: binary()

  @type validation_results :: {:ok, map()} | {:error, error_details()} | {:pending, validation_id()}

  @doc """
  Validate the resource from the given URL.

  Used by OnDemand job.
  """
  @spec validate(binary()) :: validation_results()
  def validate(url) do
    with_url(url, fn filepath ->
      validate_with_enroute(filepath) |> handle_validation_results_on_demand()
    end)
  end

  @doc """
  Continuation for the validate function (when result was pending).

  Let the OnDemand job yield while waiting for results without having the OnDemand implementation leak here.
  """
  @spec poll_validation(validation_id(), non_neg_integer()) :: validation_results()
  def poll_validation(validation_id, retries) do
    poll_validation_results(validation_id, retries) |> handle_validation_results_on_demand()
  end

  defp handle_validation_results_on_demand(validation_results) do
    case validation_results do
      {:ok, %{url: result_url, elapsed_seconds: elapsed_seconds, retries: retries}} ->
        # result_url in metadata?
        Logger.info("Result URL: #{result_url}")

        {:ok,
         %{
           "validations" => ResultsAdapter.index_messages([]),
           "metadata" => %{elapsed_seconds: elapsed_seconds, retries: retries}
         }}

      {:error, %{details: {result_url, errors}, elapsed_seconds: elapsed_seconds, retries: retries}} ->
        Logger.info("Result URL: #{result_url}")
        # result_url in metadata?
        {:ok,
         %{
           "validations" => errors |> ResultsAdapter.index_messages(),
           "metadata" => %{elapsed_seconds: elapsed_seconds, retries: retries}
         }}

      {:error, :unexpected_validation_status} ->
        Logger.error("Invalid API call to enRoute Chouette Valid")
        {:error, %{message: "enRoute Chouette Valid: Unexpected validation status"}}

      {:error, %{message: :timeout, retries: retries}} ->
        Logger.error("Timeout while fetching results on enRoute Chouette Valid")
        {:error, %{message: "enRoute Chouette Valid: Timeout while fetching results", retries: retries}}

      {:pending, validation_id} ->
        {:pending, validation_id}
    end
  end

  @spec with_resource_file(DB.ResourceHistory.t(), (Path.t() -> any())) :: any()
  def with_resource_file(resource_history, closure) do
    %DB.ResourceHistory{payload: %{"permanent_url" => permanent_url}} = resource_history
    filepath = tmp_path(resource_history)

    with_tmp_file(permanent_url, filepath, closure)
  end

  @spec with_url(binary(), (Path.t() -> any())) :: any()
  def with_url(url, closure) do
    with_tmp_file(url, tmp_path(url), closure)
  end

  @spec with_tmp_file(binary(), Path.t(), (Path.t() -> any())) :: any()
  def with_tmp_file(url, filepath, closure) do
    http_client().get!(url, compressed: false, into: File.stream!(filepath))
    closure.(filepath)
  after
    File.rm(filepath)
  end

  defp http_client, do: Transport.Req.impl()

  defp tmp_path(%DB.ResourceHistory{id: resource_history_id}) do
    System.tmp_dir!() |> Path.join("enroute_validation_netex_#{resource_history_id}")
  end

  defp tmp_path(_other) do
    System.tmp_dir!() |> Path.join("enroute_validation_netex_#{Ecto.UUID.generate()}")
  end

  def insert_validation_results(resource_history_id, result_url, metadata, errors \\ []) do
    result = ResultsAdapter.index_messages(errors)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: result,
      binary_result: ResultsAdapter.to_binary_result(result),
      digest: ResultsAdapter.digest(result),
      resource_history_id: resource_history_id,
      validator_version: validator_version(),
      command: result_url,
      max_error: ResultsAdapter.get_max_severity_error(result),
      metadata: %DB.ResourceMetadata{metadata: metadata}
    }
    |> DB.Repo.insert!()
  end

  defp validate_with_enroute(filepath) do
    setup_validation(filepath) |> poll_validation_results(0)
  end

  defp setup_validation(filepath), do: client().create_a_validation(filepath)

  def poll_validation_results(validation_id, retries) do
    case client().get_a_validation(validation_id) do
      :pending when too_many_attempts(retries) ->
        {:error, %{message: :timeout, retries: retries}}

      :pending ->
        {:pending, validation_id}

      {:successful, url, elapsed_seconds} ->
        {:ok, %{url: url, elapsed_seconds: elapsed_seconds, retries: retries}}

      {value, elapsed_seconds} when value in [:warning, :failed] ->
        {:error, %{details: client().get_messages(validation_id), elapsed_seconds: elapsed_seconds, retries: retries}}

      :unexpected_validation_status ->
        {:error, :unexpected_validation_status}
    end
  end

  defp client do
    Transport.EnRouteChouetteValidClient.Wrapper.impl()
  end
end
