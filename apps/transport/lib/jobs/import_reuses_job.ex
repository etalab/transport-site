defmodule Transport.Jobs.ImportReusesJob do
  @moduledoc """
  Import reuses from data.gouv.fr when it uses at least a dataset referenced
  on our platform.

  See https://www.data.gouv.fr/fr/datasets/catalogue-des-donnees-de-data-gouv-fr/
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  # reuses.csv export
  @csv_url "https://www.data.gouv.fr/fr/datasets/r/970aafa0-3778-4d8b-b9d1-de937525e379"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    DB.Repo.transaction(fn ->
      truncate_reuses()
      import_all_reuses()
    end)

    :ok
  end

  defp truncate_reuses, do: DB.Repo.delete_all(DB.Reuse)

  defp import_all_reuses do
    datagouv_ids = dataset_datagouv_ids()
    %{status: 200, body: body} = http_client().get!(@csv_url, decode_body: false)

    [body]
    |> CSV.decode!(headers: true, separator: ?;, escape_max_lines: 1_000)
    |> Stream.reject(fn %{"datasets" => datasets} = attributes ->
      empty_optional_fields?(attributes) or orphan_reuse?(datasets, datagouv_ids)
    end)
    |> Enum.each(fn record ->
      %DB.Reuse{} |> DB.Reuse.changeset(record) |> DB.Repo.insert!()
    end)
  end

  defp orphan_reuse?(datasets, datagouv_ids) do
    datasets |> String.split(",") |> MapSet.new() |> MapSet.disjoint?(datagouv_ids)
  end

  defp dataset_datagouv_ids do
    DB.Dataset.base_query()
    |> select([dataset: d], d.datagouv_id)
    |> DB.Repo.all()
    |> MapSet.new()
  end

  defp empty_optional_fields?(attributes) do
    attributes
    |> Map.take(["remote_url", "description", "datasets"])
    |> Map.values()
    |> Enum.all?(&(&1 == ""))
  end

  defp http_client, do: Transport.Req.impl()
end
