defmodule DB.Repo.Migrations.MetricsGBFSTargetName do
  use Ecto.Migration

  def up do
    # See https://github.com/etalab/transport-site/issues/3458
    execute "update metrics set target = replace(target, '/', '') where target like 'gbfs:%/'"
  end

  def down do
    IO.puts("no going back")
  end
end
