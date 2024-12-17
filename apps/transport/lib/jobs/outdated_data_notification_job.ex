defmodule Transport.Jobs.OutdatedDataNotificationJob do
  @moduledoc """
  This module is in charge of sending notifications to both admins and users when data is outdated.
  It is (currently) using the old DataChecker module, where there is also code for checking active/inactive datasets.
  Behaviour of this job is tested in test/transport/data_checker_test.exs.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]

  @impl Oban.Worker

  def perform(%Oban.Job{id: job_id}) do
    Transport.DataChecker.outdated_data(job_id)
    :ok
  end
end
