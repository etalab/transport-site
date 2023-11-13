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

        File.write!(state_file_path, outcome |> inspect)
      end

      Code.eval_file(state_file_path)
    end)
  end
end

folder = Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

resources
# |> Enum.filter(fn x -> x.id == 79628 end)
|> Enum.map(fn resource ->
  Downloader.handle(folder, resource)
end)
|> Enum.each(fn x -> IO.inspect(x, IEx.inspect_opts()) end)

IO.puts("============ done =============")
