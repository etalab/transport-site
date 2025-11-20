defmodule Mix.Tasks.Transport.ImportOffers do
  @moduledoc """
  Import transport offers from the Cerema.
  Run with `mix Transport.ImportOffers`.
  """
  @shortdoc "Import transport offers from the Cerema"
  use Mix.Task
  require Logger

  # From https://docs.google.com/spreadsheets/d/1ItY-ozUk2IiR0-12_6hvAS5K2Ew2bziY/edit
  @url "https://gist.githubusercontent.com/AntoineAugusti/1f43bbe8b4674905333cd7b998845c5d/raw/aa13b1c57a9a948ca28a2badd946f326c29a8093/offers.csv"

  def run(_params) do
    Logger.info("Importing offers")

    Mix.Task.run("app.start")

    DB.Repo.transaction(fn ->
      truncate_offers()
      import_offers()
    end)
  end

  defp import_offers do
    %Req.Response{status: 200, body: body} = Req.get!(@url)

    [body]
    |> CSV.decode!(headers: true, separator: ?,, escape_max_lines: 500)
    |> Enum.map(&DB.Offer.changeset(%DB.Offer{}, &1))
    |> Enum.each(&DB.Repo.insert!/1)
  end

  defp truncate_offers, do: DB.Repo.delete_all(DB.Offer)
end
