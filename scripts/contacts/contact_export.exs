#! mix run

import Ecto.Query

# NOTE: for now, edit Transport.Vault and temporarily inject the production `CLOAK_KEY` value to decrypt email
# NOTE: in `restore_db.sh`, make sure to uncomment `Truncating contact table` line when restoring a backup!

# DB.Contact.__schema__(:fields)
# |> IO.inspect(IEx.inspect_opts())

rows =
  from(DB.Contact)
  |> select([c], map(c, [:id, :first_name, :last_name, :job_title, :organization, :email]))
  |> order_by([{:asc, :id}])
  |> DB.Repo.all()
  |> CSV.encode(headers: true)
  |> Enum.into([])

File.write!("data.csv", rows)
