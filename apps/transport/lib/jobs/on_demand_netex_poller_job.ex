defmodule Transport.Jobs.OnDemandNeTExPollerJob do
  @moduledoc """
  Job in charge of polling validation results from enRoute Chouette Valid.

  Upon success it stores the result in the database.
  """

  # Max attempts doesn't really matter here as it's useful for workers failing.
  # Here we mostly poll and excepted network errors, the worker won't fail.
  @max_attempts 3

  use Oban.Worker,
    tags: ["validation"],
    max_attempts: @max_attempts,
    queue: :on_demand_validation,
    unique: [fields: [:args, :worker]]

  alias Transport.Jobs.OnDemandValidationHelpers, as: Helpers
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_1, as: ResultsAdapter
  alias Transport.Validators.NeTEx.Validator

  # Override the backoff to play nice and avoiding falling in very slow retry
  # after an important streak of snoozing (which increments the `attempt`
  # counter).
  #
  # See https://hexdocs.pm/oban/Oban.Worker.html#module-snoozing-jobs.
  @impl Worker
  def backoff(%Oban.Job{} = job) do
    corrected_attempt = @max_attempts - (job.max_attempts - job.attempt)

    Worker.backoff(%{job | attempt: corrected_attempt})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => multivalidation_id} = args, attempt: attempt}) do
    check_result(args, attempt)
    |> Helpers.handle_validation_result(multivalidation_id)
  end

  def later(validation_id, multivalidation_id, url) do
    %{validation_id: validation_id, id: multivalidation_id, permanent_url: url}
    |> new(schedule_in: {20, :seconds})
    |> Oban.insert()

    Helpers.delegated_state()
  end

  def check_result(%{"permanent_url" => url, "validation_id" => validation_id}, attempt) do
    case Validator.poll_validation(validation_id, attempt) do
      {:error, error_result} -> handle_error(error_result)
      {:ok, ok_result} -> handle_success(ok_result, url)
      {:pending, _validation_id} -> handle_pending(attempt)
    end
  end

  def handle_error(error_result) do
    error_result
    |> build_error_validation_result()
    |> Helpers.terminal_state()
  end

  def handle_success(ok_result, url) do
    ok_result
    |> build_successful_validation_result(url)
    |> Helpers.terminal_state()
  end

  def handle_pending(attempt) do
    attempt
    |> Validator.poll_interval()
    |> Helpers.snoozed_state()
  end

  defp build_successful_validation_result(%{"validations" => validation, "metadata" => metadata}, url) do
    %{
      result: validation,
      binary_result: ResultsAdapter.to_binary_result(validation),
      digest: ResultsAdapter.digest(validation),
      metadata: metadata,
      data_vis: nil,
      validator: Validator.validator_name(),
      validator_version: Validator.validator_version(),
      validated_data_name: url,
      max_error: ResultsAdapter.get_max_severity_error(validation),
      oban_args: Helpers.completed()
    }
  end

  defp build_error_validation_result(%{message: msg}) do
    %{
      oban_args: Helpers.error(msg),
      validator: Validator.validator_name(),
      validator_version: Validator.validator_version()
    }
  end
end
