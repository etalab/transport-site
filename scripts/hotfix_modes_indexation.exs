alias Transport.CounterCache

# interesting ids I kept around for experimenting with
ids_with_heterogeneous_modes = [614, 362, 146]

# TODO: move to app code (this works)
# TODO: add a couple of unit tests
# TODO: schedule a job
# MAYBE: discussion a better cache invalidation

CounterCache.resources_with_modes()
|> CounterCache.prepare_update_values()
|> DB.Repo.all()
|> IO.inspect(IEx.inspect_opts() |> Keyword.merge(limit: :infinity))
|> CounterCache.apply_all_updates!()
|> IO.inspect(IEx.inspect_opts())
