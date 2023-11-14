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

      {mode, File.read!(state_file_path) |> :erlang.binary_to_term()}
    end)
    |> Enum.into(%{})
    |> Map.put(:resource, resource)
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

  def get_zip_metadata(filename) do
    {output, exit_code} = System.cmd("unzip", ["-Z1", filename], stderr_to_stdout: true)

    cond do
      exit_code == 0 ->
        output |> String.split("\n") |> Enum.sort() |> Enum.reject(fn x -> x == "" end)

      output =~ ~r/cannot find zipfile directory|signature not found/ ->
        :corrupt

      true ->
        raise "should not happen"
    end
  end

  def compare_json(file_1, file_2) do
    {output, 0} = System.shell("scripts/compare-json.sh #{file_1} #{file_2} 2>&1")
    output == ""
  end

  def compare_csv(file_1, file_2) do
    File.read!(file_1) |> String.split("\n") |> List.first() ==
      File.read!(file_2) |> String.split("\n") |> List.first()
  end
end

IO.puts("Total considered resources: count=#{resources |> Enum.count()}")

{all_ok, not_all_ok} =
  stream
  |> Enum.split_with(fn x -> match?(%{legacy: {:ok, _, _}, req: {:ok, _, _}}, x) end)

IO.puts("Download OK for both req & httpoison: count=#{all_ok |> Enum.count()}")
IO.write("How many OK files are not equivalent in a way or another? ")

all_ok
|> Stream.map(fn x ->
  {:ok, file_1, _} = x[:legacy]
  {:ok, file_2, _} = x[:req]
  same_checksum = Comparer.checksum(file_1, :cached) == Comparer.checksum(file_2, :cached)
  Map.put(x, :same_checksum, same_checksum)
end)
|> Stream.filter(fn x -> !x[:same_checksum] end)
|> Stream.map(fn x ->
  {:ok, file_1, _} = x[:legacy]
  {:ok, file_2, _} = x[:req]

  x =
    if x.resource.format == "GTFS" do
      same_gtfs = Comparer.get_zip_metadata(file_1) == Comparer.get_zip_metadata(file_2)
      Map.put(x, :same_gtfs, same_gtfs)
    else
      x
    end

  x =
    if x.resource.format == "geojson" do
      same_json = Comparer.compare_json(file_1, file_2)
      Map.put(x, :same_json, same_json)
    else
      x
    end

  x =
    if x.resource.format == "shp" do
      same_shp = Comparer.get_zip_metadata(file_1) == Comparer.get_zip_metadata(file_2)
      Map.put(x, :same_shp, same_shp)
    else
      x
    end

  x =
    if x.resource.format == "NeTEx" do
      # at this point, the non-equal NeTEx are all zip containing zips
      same_zipped_netex = Comparer.get_zip_metadata(file_1) == Comparer.get_zip_metadata(file_2)
      Map.put(x, :same_zipped_netex, same_zipped_netex)
    else
      x
    end

  x =
    if x.resource.format == "csv" do
      same_csv_headers = Comparer.compare_csv(file_1, file_2)
      Map.put(x, :same_csv_headers, same_csv_headers)
    else
      x
    end

  x
end)
|> Stream.reject(fn x -> x.resource.format == "GTFS" && x[:same_gtfs] end)
|> Stream.reject(fn x -> x.resource.format == "geojson" && x[:same_json] end)
|> Stream.reject(fn x -> x.resource.format == "shp" && x[:same_shp] end)
|> Stream.reject(fn x -> x.resource.format == "NeTEx" && x[:same_zipped_netex] end)
|> Stream.reject(fn x -> x.resource.format == "csv" && x[:same_csv_headers] end)
|> Enum.count()
|> IO.puts()

IO.puts("Download not OK for at least one: count=#{not_all_ok |> Enum.count()}")

{same_error, not_same_error} =
  Enum.split_with(not_all_ok, fn x ->
    case x do
      %{req: {:error, err1}, legacy: {:error, err2}} ->
        err1 == err2 && err1 |> String.starts_with?("Got a non 200 status")

      _ ->
        false
    end
  end)

IO.puts(
  "Download not OK but req & httpoison lead to same http status error: count=" <>
    (same_error |> Enum.count() |> inspect)
)

IO.puts("Other: " <> (not_same_error |> Enum.count() |> inspect()))

not_same_error
|> Enum.frequencies_by(fn x -> %{req: x[:req] |> elem(0), legacy: x[:legacy] |> elem(0)} end)
|> IO.inspect(IEx.inspect_opts())

not_same_error
|> Enum.map(fn x -> x[:resource].url end)
|> Enum.each(fn x -> IO.puts(x) end)

IO.puts("============ done =============")
