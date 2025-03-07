defmodule Transport.Jobs.ImportReusesJob do
  @moduledoc """
  Import all `transport_and_mobility` reuses from data.gouv.fr.
  See:
  - https://www.data.gouv.fr/fr/datasets/catalogue-des-donnees-de-data-gouv-fr/
  - https://tabular-api.data.gouv.fr/api/resources/970aafa0-3778-4d8b-b9d1-de937525e379/data/?page=1&page_size=50&topic__exact=transport_and_mobility
  """
  use Oban.Worker, max_attempts: 3

  @start_url "https://tabular-api.data.gouv.fr/api/resources/970aafa0-3778-4d8b-b9d1-de937525e379/data/?page=1&page_size=50&topic__exact=transport_and_mobility"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    DB.Repo.transaction(fn ->
      DB.Repo.delete_all(DB.Reuse)
      import_page_of_reuses(@start_url)
    end)

    :ok
  end

  def import_page_of_reuses(nil), do: :ok

  def import_page_of_reuses(url) do
    case http_client().get(url, []) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        body
        |> Map.fetch!("data")
        |> Enum.each(fn record ->
          %DB.Reuse{} |> DB.Reuse.changeset(record) |> DB.Repo.insert!()
        end)

        import_page_of_reuses(body["links"]["next"])

      _ ->
        :error
    end
  end

  defp http_client, do: Transport.Req.impl()
end
