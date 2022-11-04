Mix.install([
  {:req, ">= 0.0.0"}
])

require Logger
Logger.info("Starting...")

%{body: datasets} = Req.get!("http://localhost:5000/api/datasets")

datasets
|> Enum.map(& &1["id"])
|> Task.async_stream(
  fn id ->
    %{body: body, status: status} =
      Req.get!("http://localhost:5000/api/datasets/#{id}", retry: :never)

    cond do
      status == 500 ->
        {status, body |> String.split("\n") |> List.first() |> String.split("at") |> List.first()}

      true ->
        status
    end
  end,
  max_concurrency: 50
)
|> Enum.map(fn {:ok, id} -> id end)
|> Enum.group_by(& &1)
|> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
|> Enum.into(%{})
|> IO.inspect(IEx.inspect_opts())

Logger.info("Done...")
