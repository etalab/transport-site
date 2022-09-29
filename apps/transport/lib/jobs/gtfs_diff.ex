defmodule Transport.Jobs.GtfsDiff do
  @moduledoc """
  Job in charge of computing a diff between two GTFS files
  """
  use Oban.Worker, max_attempts: 1
  # require Logger
  # import Ecto.Query
  # alias DB.{Dataset, Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gtfs_url_1" => gtfs_url_1, "gtfs_url_2" => gtfs_url_2}}) do
    :ok
    # unzip_1 = Transport.Beta.GTFS.unzip(path_gtfs_1)
    # unzip_2 = Transport.Beta.GTFS.unzip(path_gtfs_2)

    # diff = Transport.Beta.GTFS.diff(unzip_1, unzip_2)

    # diff_summary =
    #   diff
    #   |> diff_summary()

    # diff_output = diff |> Transport.Beta.GTFS.dump_diff() |> String.split("\r\n")

    # socket =
    #   socket
    #   |> assign(:diff_summary, diff_summary)
    #   |> assign(:diff_output, diff_output)

    # File.rm!(path_gtfs_1)
    # File.rm!(path_gtfs_2)    :ok
  end
end
