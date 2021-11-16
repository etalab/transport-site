Mix.install([
  {:req, "~> 0.2.0"}
])

defmodule Download do
  def download do
    IO.puts("Starting....")

    url = "https://zenbus.net/gtfs/static/download.zip?dataset=fontenay"

    response =
      Req.build(:get, url)
      |> Req.run!()

    IO.inspect(response, IEx.inspect_opts())

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    filename = "save-#{timestamp}.zip"
    IO.puts("Writing #{filename}...")
    File.write!(filename, response.body)
  end

  def analyse(file) do
    IO.puts("Analyzing file #{file}...")

    {:ok, result} = :zip.list_dir(file |> to_char_list)

    result
    |> Enum.reject(&match?({:zip_comment, _}, &1))
    |> IO.inspect(IEx.inspect_opts())

    {output, 0} = System.cmd("unzip", ["-lv", file])
    IO.puts(output)

    IO.puts("Done")
  end
end

Path.wildcard("*.zip")
# |> Enum.take(1)
|> Enum.each(&Download.analyse/1)
