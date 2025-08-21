defmodule Script do
  @moduledoc """
  Script to debug and inspect current implementation of validation rules for the
  French NeTEx profile.
  """

  import Transport.NeTEx.FrenchProfile

  def go do
    with_file("chouette_ruleset.json", &ruleset/1)
    with_file("chouette_ruleset.md", &markdown/1)
  end

  defp with_file(file, proc) do
    {:ok, device} = StringIO.open("")

    proc.(device)

    _ = File.rm(file)
    File.touch!(file)

    content = StringIO.flush(device)

    File.write(file, content)
  end
end

Script.go()
