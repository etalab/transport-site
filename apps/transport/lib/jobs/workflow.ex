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

      Transport.Jobs.Workflow.Notifier.notify_workflow(%{
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
  be Jason encoded. There is the kw_m helper function to transform a a keword list to a map if needed.
  """
  use Oban.Worker, tags: ["workflow"], max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"jobs" => jobs, "first_job_args" => first_job_args}
      }) do
    :ok = Oban.Notifier.listen([:gossip])
    execute_jobs(jobs, first_job_args)
    :ok
  end

  defp execute_jobs([job], args), do: insert_job(job, args)

  defp execute_jobs([job | tail], args) do
    %{id: job_id} = insert_job(job, args)

    receive do
      # each job produces an output than can be used by the next job in the workflow
      {:notification, :gossip, %{"success" => true, "job_id" => ^job_id, "output" => job_output}} ->
        execute_jobs(tail, job_output)

      {:notification, :gossip, %{"success" => false, "job_id" => ^job_id} = notif} ->
        reason = notif |> Map.get("reason", "unknown reason")
        {:error, "Job #{job_id} has failed: #{reason}. Workflow is stopping here"}
    end
  end

  def handle_event(
        [:oban, :engine, :discard_job, :exception],
        _,
        %{id: job_id, error: error, job: %{meta: %{"workflow" => true}}},
        nil
      ) do
    notify_workflow(%{"success" => false, "job_id" => job_id, "reason" => error})
  end

  def insert_job([job_name, custom_args, options], args) do
    # if custom args are given they are merged with the job arguments
    # options are job options (unique, ...)
    args = Map.merge(args, custom_args)
    options = options |> m_kw()

    # we add a meta information to show the job is part of a workflow
    # and to track a possible failure
    meta =
      options
      |> Keyword.get(:meta, %{})
      |> Map.put(:workflow, true)

    options = options |> Keyword.put(:meta, meta)

    args |> String.to_existing_atom(job_name).new(options) |> Oban.insert!()
  end

  def insert_job(job_name, args) do
    args |> String.to_existing_atom(job_name).new(meta: %{workflow: true}) |> Oban.insert!()
  end

  defmodule Notifier do
    @callback notify_workflow([map] | map) :: :ok

    def impl, do: Application.fetch_env!(:transport, :workflow_notifier)

    def notify_workflow(args), do: impl().notify_workflow(args)
  end

  defmodule ObanNotifier do
    @behaviour Transport.Jobs.Workflow.Notifier

    @impl Transport.Jobs.Workflow.Notifier
    def notify_workflow(args) do
      Oban.Notifier.notify(Oban, :gossip, args)
    end
  end

  defmodule ProcessNotifier do
    @behaviour Transport.Jobs.Workflow.Notifier

    @impl Transport.Jobs.Workflow.Notifier
    def notify_workflow(args) do
      send(
        :workflow_process,
        {:notification, :gossip, args}
      )

      :ok
    end
  end

  def handle_event(
        [:oban, :job, :exception],
        _,
        # check max_attempts is reached
        %{
          attempt: n,
          id: job_id,
          error: error,
          job: %{max_attempts: n, meta: %{"workflow" => true}}
        },
        nil
      ) do
    Notifier.notify_workflow(%{"success" => false, "job_id" => job_id, "reason" => error})
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

  iex> m_kw(%{})
  []

  iex> m_kw(%{"a" => 1})
  [a: 1]

  iex> m_kw(%{"a" => %{"b" => %{"c" => 1}}, "d" => 1})
  [a: [b: [c: 1]], d: 1]
  """
  def m_kw(%{} = m) do
    m |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), m_kw(v)} end)
  end

  def m_kw(v) when is_binary(v), do: String.to_existing_atom(v)
  def m_kw(v), do: v

  @doc """
  Converts nested lists of keywords to nested maps
  map keys are atoms

  iex> kw_m([])
  %{}

  iex> kw_m([a: 1])
  %{a: 1}

  iex> kw_m([a: [b: [c: 1]], d: 1])
  %{a: %{b: %{c: 1}}, d: 1}
  """
  def kw_m([]), do: %{}

  def kw_m([{k, v}]) when is_list(v) do
    [{k, kw_m(v)}] |> Enum.into(%{})
  end

  def kw_m([{_, _}] = kw) do
    kw |> Enum.into(%{})
  end

  def kw_m([head | tail]) do
    [head] |> kw_m() |> Map.merge(kw_m(tail))
  end
end
