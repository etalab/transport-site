defmodule Transport.Jobs.Workflow do
  @moduledoc """
   Handle a simple workflow of jobs.
  """
  use Oban.Worker, tags: ["workflow"], max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"jobs" => jobs, "first_job_args" => first_job_args} = workflow_args}) do
    timeout = workflow_args |> Map.get("timeout", 30_000)
    :ok = Oban.Notifier.listen([:gossip])
    execute_jobs(jobs, first_job_args, timeout)
    :ok
  end

  defp execute_jobs([job], args, _), do: insert_job(job, args)

  defp execute_jobs([job | tail], args, timeout) do
    %{id: job_id} = insert_job(job, args)

    receive do
      # each job produces an output than can be used by the next job in the workflow
      {:notification, :gossip, %{"complete" => ^job_id, "output" => job_output}} ->
        execute_jobs(tail, job_output, timeout)
    after
      timeout -> {:timeout, job}
    end
  end

  def insert_job([job_name, custom_args, options], args) do
    # if custom args are given they are merged with the job arguments
    # options are job options (unique, ...)
    args = Map.merge(args, custom_args)
    options = m_kw(options)

    args |> String.to_existing_atom(job_name).new(options) |> Oban.insert!()
  end

  def insert_job(job_name, args) do
    args |> String.to_existing_atom(job_name).new() |> Oban.insert!()
  end

  def notify_workflow(args) do
    Oban.Notifier.notify(Oban, :gossip, args)
  end

  def m_kw(%{} = m) do
    m |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), m_kw(v)} end)
  end

  def m_kw(v) when is_binary(v), do: String.to_existing_atom(v)
  def m_kw(v), do: v

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
