defmodule Transport.Jobs.GBFSOperatorsNotificationJob do
  @moduledoc """
  Job in charge of detecting GBFS feeds for which we cannot detect the system operator
  and sending a notification email to our team.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_feeds() |> send_email()
  end

  def relevant_feeds do
    DB.Resource.base_query()
    |> where([resource: r], r.is_available and r.format == "gbfs")
    |> DB.Repo.all()
    |> Enum.filter(fn %DB.Resource{url: url} -> is_nil(Transport.GBFSMetadata.operator(url)) end)
  end

  def send_email([]), do: :ok

  def send_email(resources) do
    resources
    |> Transport.AdminNotifier.unknown_gbfs_operator_feeds()
    |> Transport.Mailer.deliver()

    :ok
  end
end
