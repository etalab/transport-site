defmodule Transport.Jobs.ResourceHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceHistoryJob`
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"]
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(_job) do
    Transport.S3.create_bucket_if_needed!(:history)

    duplicates =
      Resource
      |> where([r], not is_nil(r.datagouv_id))
      |> group_by([r], r.datagouv_id)
      |> having([r], count(r.datagouv_id) > 1)
      |> select([r], r.datagouv_id)
      |> Repo.all()

    datagouv_ids =
      Resource
      |> where([r], not is_nil(r.url) and not is_nil(r.title) and not is_nil(r.datagouv_id))
      |> where([r], r.format == "GTFS" or r.format == "NeTEx")
      |> where([r], r.datagouv_id not in ^duplicates)
      |> where([r], not r.is_community_resource)
      |> select([r], r.datagouv_id)
      |> Repo.all()

    datagouv_ids
    |> Enum.each(fn datagouv_id ->
      %{datagouv_id: datagouv_id}
      |> Transport.Jobs.ResourceHistoryJob.new()
      |> Oban.insert()
    end)

    :ok
  end
end

defmodule Transport.Jobs.ResourceHistoryJob do
  @moduledoc """
  Job historicising a single resource
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"]
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"datagouv_id" => datagouv_id}}) do
    Logger.info("Running ResourceHistoryJob for #{datagouv_id}")

    download_resource(datagouv_id)

    :ok
  end

  defp download_resource(datagouv_id) do
    resource = Resource |> where([r], r.datagouv_id == ^datagouv_id) |> Repo.one!()

    file_path = System.tmp_dir!() |> Path.join("resource_#{datagouv_id}_download")

    # TO DO stream file to disk
    # TO DO verify headers (content-type) and maybe provide alerts to providers!
    %{status: 200, body: body} = Unlock.HTTP.Client.impl().get!(resource.url, [])
    Logger.debug("Saving resource #{datagouv_id} to #{file_path}")
    File.write!(file_path, body)

    file_path
  end
end
