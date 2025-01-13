defmodule Transport.Jobs.Workflow do
  @moduledoc """
   Handle a simple workflow of jobs.

   # Usage
    ```
    Transport.Jobs.Workflow.new(%{
      "jobs" => jobs,
      "first_job_args" => first_job_args
    })
    ```
    Where `jobs` is a list of jobs, and `first_job_args` are the arguments passed to the first job of the list.
    Each job of the list is expected to "notify" upon completion:

    ```
    defmodule JobA do
    use Oban.Worker

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
      # perform job here
      # ...

      Transport.Jobs.Workflow.Notifier.notify_workflow(job, %{
        "success" => true,
        "job_id" => job.id,
        "output" => %{"some_id" => some_id}
      })

      :ok
    end
  end
    ```
  The `output` map will be passed to the next job of the workflow as its arguments.

  ## Note :
  It is possible to create a workflow of jobs with a simple list:
  `jobs = [JobA, JobB]`

  Or to specify custom arguments and/or custom job options:
  `jobs = [JobA, [JobB, custom_arguments, custom_options]]`

  `custom_arguments` is expected to be a map of arguments, that get merged with the previous job output.

  For example:
  `jobs = [JobA, [JobB, %{"forced" => true}, %{}]]`

  `custom_options` is expected to be a map:
  `jobs = [JobA, [JobB, %{}, %{queue: :heavy}]]`

  It would have been more natural for `custom_options` to be a keyword list, but Oban can just accept maps as job arguments, as keyword list cannot
  be Jason encoded. There is the kw_to_map helper function to transform a keword list to a map if needed.
  """
  use Oban.Worker, tags: ["workflow"], max_attempts: 3, queue: :workflow
  alias Transport.Jobs.Workflow.Notifier

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"jobs" => jobs, "first_job_args" => first_job_args}
        } = workflow_job
      ) do
    :ok = Oban.Notifier.listen([:gossip])
    execute_jobs(jobs, first_job_args, workflow_job)
  end

  defp execute_jobs([job], args, workflow_job) do
    insert_job(job, args, workflow_job)
    :ok
  end

  defp execute_jobs([job | tail], args, workflow_job) do
    case insert_job(job, args, workflow_job) do
      %{id: job_id, worker: worker, conflict?: true} ->
        {:error, "Job #{job_id} (#{worker}) has a conflict. Workflow is stopping here"}

      %{id: job_id} ->
        receive do
          # each job produces an output than can be used by the next job in the workflow
          {:notification, :gossip, %{"success" => true, "job_id" => ^job_id, "output" => job_output}} ->
            execute_jobs(tail, job_output, workflow_job)

          {:notification, :gossip, %{"success" => false, "job_id" => ^job_id} = notif} ->
            reason = notif |> Map.get("reason", "unknown reason")
            {:error, "Job #{job_id} has failed: #{reason}. Workflow is stopping here"}
        end
    end
  end

  @spec insert_job(binary | [...], map(), Oban.Job.t()) :: Oban.Job.t()
  def insert_job([job_name, custom_args, options], args, workflow_job)
      when is_map(custom_args) and is_map(options) do
    # if custom args are given they are merged with the job arguments
    # options are job options (unique, ...)
    args = Map.merge(args, custom_args)
    options = options |> map_to_kw()

    # we add a meta information to show the job is part of a workflow
    # and to track a possible failure
    meta =
      options
      |> Keyword.get(:meta, %{})
      |> Map.put(:workflow, true)
      |> Map.put(:workflow_job_id, workflow_job.id)

    options = options |> Keyword.put(:meta, meta)

    args |> String.to_existing_atom(job_name).new(options) |> Oban.insert!()
  end

  def insert_job(job_name, args, workflow_job) do
    args
    |> String.to_existing_atom(job_name).new(meta: %{workflow: true, workflow_job_id: workflow_job.id})
    |> Oban.insert!()
  end

  defmodule Notifier do
    @moduledoc """
    a behavior that let us choose the method to send notifications
    """
    @callback notify_workflow(map(), [map] | map) :: :ok
    def impl, do: Application.fetch_env!(:transport, :workflow_notifier)
    def notify_workflow(job, args), do: impl().notify_workflow(job, args)
  end

  defmodule ObanNotifier do
    @moduledoc """
    a wrapper around Oban.Notifier.notify
    """
    @behaviour Transport.Jobs.Workflow.Notifier

    @impl Transport.Jobs.Workflow.Notifier
    def notify_workflow(%{meta: %{"workflow" => true}}, args) do
      Oban.Notifier.notify(Oban, :gossip, args)
    end

    def notify_workflow(_job, _args), do: nil
  end

  defmodule ProcessNotifier do
    @moduledoc """
    Used when testing, because Oban.Notifier.notify do not work in sandboxed environment
    see https://hexdocs.pm/oban/Oban.Notifiers.Postgres.html#module-caveats
    So we just send the message manually
    """
    @behaviour Transport.Jobs.Workflow.Notifier

    @impl Transport.Jobs.Workflow.Notifier
    def notify_workflow(%{meta: %{"workflow" => true}}, args) do
      send(
        :workflow_process,
        {:notification, :gossip, args}
      )

      :ok
    end

    def notify_workflow(_job, _args), do: nil
  end

  @doc """
  This function is triggered by Oban Telemetry events when a job fails
  """
  def handle_event(
        [:oban, :job, :exception],
        _,
        # max_attempts is reached
        %{
          attempt: n,
          id: job_id,
          error: error,
          job: %{max_attempts: n, meta: %{"workflow" => true}}
        },
        nil
      ) do
    # `error` can be an error message or an `Oban.TimeoutError` exception.
    # ````
    # %Oban.TimeoutError{
    #   message: "Transport.Jobs.ResourceHistoryJob timed out after 1000ms",
    #   reason: :timeout
    # }
    # ```
    Notifier.notify_workflow(%{meta: %{"workflow" => true}}, %{
      "success" => false,
      "job_id" => job_id,
      "reason" => inspect(error)
    })
  end

  def handle_event(
        [:oban, :job, :exception],
        _,
        _,
        nil
      ),
      do: nil

  @doc """
  Converts nested maps to nested lists of keywords
  map keys are binaries

  iex> map_to_kw(%{})
  []

  iex> map_to_kw(%{"a" => 1})
  [a: 1]

  iex> map_to_kw(%{"a" => %{"b" => %{"c" => 1}}, "d" => 1})
  [a: [b: [c: 1]], d: 1]
  """
  def map_to_kw(%{} = m) do
    m |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), map_to_kw(v)} end)
  end

  def map_to_kw(v) when is_binary(v), do: String.to_existing_atom(v)
  def map_to_kw(v), do: v

  @doc """
  Converts nested lists of keywords to nested maps
  map keys are atoms

  iex> kw_to_map([])
  %{}

  iex> kw_to_map([a: 1])
  %{a: 1}

  iex> kw_to_map([a: [b: [c: 1]], d: 1])
  %{a: %{b: %{c: 1}}, d: 1}
  """
  def kw_to_map([]), do: %{}

  def kw_to_map([{k, v}]) when is_list(v) do
    [{k, kw_to_map(v)}] |> Enum.into(%{})
  end

  def kw_to_map([{_, _}] = kw) do
    kw |> Enum.into(%{})
  end

  def kw_to_map([head | tail]) do
    [head] |> kw_to_map() |> Map.merge(kw_to_map(tail))
  end
end
