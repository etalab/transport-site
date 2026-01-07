defmodule Transport.Jobs.VisitProxyStatisticsJob do
  @moduledoc """
  This job sends emails to producers who are using the transport proxy.
  It tells them to look at their producer space to see statistics.
  """
  use Oban.Worker, max_attempts: 3
  alias Transport.Jobs.VisitStatisticsBase

  @notification_reason :visit_proxy_statistics

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: %DateTime{} = scheduled_at}) do
    VisitStatisticsBase.perform_job(
      scheduled_at,
      @notification_reason,
      &DB.Resource.served_by_proxy?/1,
      &Transport.UserNotifier.visit_proxy_statistics/1
    )
  end

  @doc """
  Public function for backward compatibility and testing.
  """
  def relevant_contacts do
    VisitStatisticsBase.relevant_contacts(&DB.Resource.served_by_proxy?/1)
  end
end
