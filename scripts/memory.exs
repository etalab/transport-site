:application.start(:sasl)
:application.start(:os_mon)

# https://www.erlang.org/doc/man/memsup.html#get_system_memory_data-0
output = :memsup.get_system_memory_data()

IO.inspect(output, IEx.inspect_opts())

# [
#   # The amount of free memory available to the Erlang emulator for allocation.
#   free_memory: 175210496,
#   # The amount of memory available to the whole operating system.
#   # This may well be equal to total_memory but not necessarily.
#   system_total_memory: 17179869184,
#   # The total amount of memory available to the Erlang emulator, allocated and free.
#   # May or may not be equal to the amount of memory configured in the system.
#   total_memory: 17179869184
# ]
