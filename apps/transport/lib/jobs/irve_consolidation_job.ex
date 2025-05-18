defmodule Transport.Jobs.IRVEConsolidationJob do
  @moduledoc """
  Nightly production of IRVE consolidation.
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    IO.inspect(args, IEx.inspect_opts())

    filter =
      if args[:limit] do
        fn stream -> stream |> Enum.take(args[:limit]) end
      else
        nil
      end

    Transport.IRVE.Consolidation.build_aggregate_and_report!(%{filter: filter})
  end
end
