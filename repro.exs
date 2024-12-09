# Reproduce the issue introduced with migrations.
# I will use that to bisect the regression.
System.shell("mix ecto.drop")
System.shell("mix ecto.create")
System.shell("mix ecto.migrate")
