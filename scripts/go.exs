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

stream =
  resources
  |> Task.async_stream(
    fn x -> Downloader.handle(folder, x) end,
    max_concurrency: 10,
    timeout: :infinity
  )
  |> Stream.map(fn {:ok, x} -> x end)

# TODOS:
# - compter ceux qui sont 200 (donc :ok) des deux côtés, et vérifier la cohérence de la donnée approximativement

defmodule Comparer do
  # compute checksum, using a checksum file for persistence since this is a costly operation
  def checksum(file, :cached) do
    checksum_file = file <> ".checksum"

    unless File.exists?(checksum_file) do
      checksum = :crypto.hash(:md5, File.read!(file)) |> Base.encode16()
      File.write!(checksum_file, checksum)
    end

    File.read!(checksum_file)
  end
end

stream
|> Stream.filter(fn x -> match?([{:ok, _, _}, {:ok, _, _}], x) end)
|> Stream.filter(fn x ->
  [{:ok, file_1, _}, {:ok, file_2, _}] = x
  Comparer.checksum(file_1, :cached) != Comparer.checksum(file_2, :cached)
end)
|> Enum.count()
|> IO.puts()

# - compter ceux qui sont 200 que pour httpoison, et par pour req: ce sont des régressions à étudier. Voir le contenu,
#   mais aussi l'état. Je pense que les erreurs d'encodage d'urls porteront là dessus.
# - compter ceux qui sont 200 pour req, mais pas pour httpoison. Vérifier que ce sont bien des améliorations
# - voir ceux qui sont non-200 des deux côtés, et comparer.

IO.puts("============ done =============")
