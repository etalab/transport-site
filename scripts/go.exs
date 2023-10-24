import Ecto.Query

Logger.configure(level: :info)

resource = DB.Resource
|> order_by(desc: :id)
|> limit(1)
|> DB.Repo.one!()
# |> IO.inspect(IEx.inspect_opts)

IO.puts resource.url

job = %Oban.Job{args: %{"resource_id" => resource.id}}

Transport.Jobs.ResourceHistoryJob.perform(job)

IO.puts "done!"
