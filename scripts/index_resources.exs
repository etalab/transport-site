resources =
  DB.Resource
  |> DB.Repo.all()

# count
resources
|> Enum.count()
|> IO.inspect()

# proportion de ressources par formats
defmodule StreamTools do
  def each_with_index(stream, function) do
    stream
    |> Stream.with_index()
    |> Stream.each(function)
    |> Stream.map(fn {item, _index} -> item end)
  end
end

df =
  resources
  |> StreamTools.each_with_index(fn {item, index} ->
    if index == 0 do
      IO.puts("====== échantillon ======")
      IO.inspect(item, IEx.inspect_opts())
      IO.puts("")
    end
  end)
  |> Enum.map(fn r ->
    %{
      id: r.id,
      url: r.url,
      title: r.title,
      supposed_format: r.format,
      description: r.description
    }
  end)
  |> Explorer.DataFrame.new()
  |> IO.inspect(IEx.inspect_opts())

df[:supposed_format]
|> IO.inspect(IEx.inspect_opts())
|> Explorer.Series.frequencies()
|> IO.inspect(IEx.inspect_opts())
