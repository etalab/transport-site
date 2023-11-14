# Logger.configure(level: :debug)

resources = Transport.Jobs.ResourceHistoryAndValidationDispatcherJob.resources_to_historise()

defmodule Downloader do
  def handle(folder, resource) do
    [:req, :legacy]
    |> Enum.map(fn mode ->
      file_path = Path.join(folder, "#{mode}-#{resource.id}.dat")
      state_file_path = file_path <> ".state"

      unless File.exists?(state_file_path) do
        outcome =
          Transport.Jobs.ResourceHistoryJob.download_resource(mode, resource, file_path)

        unless outcome |> elem(0) == :ok do
          File.rm(file_path)
        end

        File.write!(state_file_path, outcome |> :erlang.term_to_binary())
      end

      File.read!(state_file_path) |> :erlang.binary_to_term()
    end)
  end
end

folder = Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

resources
|> Task.async_stream(
  fn x -> Downloader.handle(folder, x) end,
  max_concurrency: 10,
  timeout: :infinity
)
|> Stream.map(fn {:ok, x} -> x end)
|> Stream.each(fn x -> IO.inspect(x, IEx.inspect_opts()) end)
|> Stream.run()

IO.puts("============ done =============")
