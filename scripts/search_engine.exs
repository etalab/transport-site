#! mix run

import Ecto.Query

datasets =
  from(d in DB.Dataset,
    join: r in assoc(d, :resources),
    preload: :resources
  )
  |> DB.Repo.all()

[one_dataset | _] = datasets

payload =
  %{
    id: one_dataset.id,
    datagouv_id: one_dataset.datagouv_id,
    title: one_dataset.custom_title,
    description: one_dataset.description,
    formats: one_dataset.resources |> Enum.map(& &1.format)
  }
  |> IO.inspect(IEx.inspect_opts())
