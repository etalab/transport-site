defmodule Mix.Tasks.Transport.ImportInseeAom do
  @moduledoc """
  Import the links between Commune and AOM
  """

  use Mix.Task
  import Ecto.Query
  alias Transport.{Commune, Repo}

  def run(params) do
    unless params[:no_start], do: Mix.Task.run("app.start", [])

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get("https://www.data.gouv.fr/fr/datasets/r/55762099-50a4-4c25-8bf1-15e3a4f3308f", [], hackney: [follow_redirect: true]),
         {:ok, stream} <- StringIO.open(body) do
      stream
      |> IO.binstream(:line)
      |> CSV.decode(separator: ?\t)
      |> Enum.each(fn {:ok, [aom, insee]} ->
        Repo.update_all(
          from(c in Commune, where: c.insee == ^insee),
          set: [aom_res_id: String.to_integer(aom)])
      end)
    end
  end
end
