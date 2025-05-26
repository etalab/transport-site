defmodule Transport.Jobs.UpdateCounterCacheJob do
  @moduledoc """
  This job is in charge updating the counter cache for `DB.Resource` with modes and features
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: args}) when is_nil(args) or args == %{} do
    Transport.CounterCache.cache_modes_features_on_resources()

    :ok
  end
end
