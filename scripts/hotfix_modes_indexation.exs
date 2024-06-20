alias Transport.CounterCache

# interesting ids I kept around for experimenting with
ids_with_heterogeneous_modes = [614, 362, 146]

# TODO: add a couple of unit tests
# TODO: schedule a job
# MAYBE: discussion a better cache invalidation
CounterCache.cache_modes_on_resources() |> IO.inspect(IEx.inspect_opts())
