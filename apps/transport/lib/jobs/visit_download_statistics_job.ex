defmodule Transport.Jobs.VisitDownloadStatisticsJob do
  @moduledoc """
  This job sends emails to producers who have at least a resource hosted on data.gouv.fr
  It tells them to look at their producer space to see statistics.
  """
  use Oban.Worker, max_attempts: 3
  alias Transport.Jobs.VisitStatisticsBase

  @notification_reason :visit_download_statistics

  @impl Oban.Worker
  def perform(%Oban.Job{scheduled_at: %DateTime{} = scheduled_at}) do
    VisitStatisticsBase.perform_job(
      scheduled_at,
      @notification_reason,
      &DB.Resource.hosted_on_datagouv?/1,
      &Transport.UserNotifier.visit_download_statistics/1
    )
  end

  @doc """
  Public function for backward compatibility and testing.
  """
  def relevant_contacts do
    VisitStatisticsBase.relevant_contacts(&DB.Resource.hosted_on_datagouv?/1)
  end
end
