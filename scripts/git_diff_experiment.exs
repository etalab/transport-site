Mix.install([
  {:git_diff, "~> 0.6.3"},
  {:req, "~> 0.3.0"},
  {:unzip, "~> 0.7.0"}
])

defmodule GTFSCompare do
  require Logger

  def maybe_download(url, local_file) do
    unless File.exists?(local_file) do
      Logger.info("Downloading #{url} to #{local_file}...")
      %{status: 200, body: body} = Req.get!(url, decode_body: false)
      File.write!(local_file, body)
    end
  end
end

base =
  "https://transport-data-gouv-fr-resource-history-prod.cellar-c2.services.clever-cloud.com/b5873d02-043e-447a-8433-0a3be706efc8/b5873d02-043e-447a-8433-0a3be706efc8.20220607.120433.286304.zip"

new =
  "https://transport-data-gouv-fr-resource-history-prod.cellar-c2.services.clever-cloud.com/b5873d02-043e-447a-8433-0a3be706efc8/b5873d02-043e-447a-8433-0a3be706efc8.20220608.180932.003492.zip"

unless File.exists?("downloads"), do: File.mkdir!("downloads")
GTFSCompare.maybe_download(base, "downloads/base.zip")
GTFSCompare.maybe_download(new, "downloads/new.zip")
