defmodule Transport.DataValidation.Supervisor do
  @moduledoc """
  Supervisor for all of data validation aggregates.
  """

  use Supervisor
  alias Transport.DataValidation.Aggregates

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: :data_validation_sup)
  end

  def start_dataset(download_url) when is_binary(download_url) do
    Supervisor.start_child(:data_validation_sup, [download_url])
  end

  def init(_arg) do
    supervise(
      [worker(Aggregates.Dataset, [], restart: :transient)],
      strategy: :simple_one_for_one
    )
  end
end
