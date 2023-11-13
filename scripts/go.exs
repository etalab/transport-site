# Logger.configure(level: :debug)

resources = Transport.Jobs.ResourceHistoryAndValidationDispatcherJob.resources_to_historise()

defmodule Downloader do
  def handle(folder, resource) do
    [:req, :legacy]
    |> Enum.each(fn mode ->
      file_path = Path.join(folder, "#{mode}-#{resource.id}.dat")

      unless File.exists?(file_path) do
        IO.puts("Saving #{file_path}")
        Transport.Jobs.ResourceHistoryJob.download_resource(:req, resource, file_path)
      end
    end)
  end
end

folder = Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

resources
|> Enum.each(fn resource ->
  Downloader.handle(folder, resource)
end)
