defmodule Transport.Screens do
  import Ecto.Query

  def resources do
    DB.Resource
    |> select([p], map(p, [:id, :format, :datagouv_id]))
  end

  def resources_with_duplicate_datagouv_id do
    resources
    |> DB.Repo.all()
    |> Enum.group_by(fn x -> x[:datagouv_id] end)
    |> Enum.filter(fn {a, b} -> b |> Enum.count() > 1 end)
  end

  def resources_with_duplicate_datagouv_id(markdown: true) do
    resources_with_duplicate_datagouv_id()
    |> Enum.map(fn {a, b} ->
      [
        "#### resource_datagouv_id=#{a |> inspect}\n\n",
        b |> Enum.map(fn x -> "* https://transport.data.gouv.fr/resources/#{x[:id]}" end)
      ]
    end)
    |> List.flatten()
    |> Enum.join("\n")
    |> Kino.Markdown.new()
  end
end
