defmodule FTPDownloader do
  require Logger

  def download(url) do
    Logger.info "Initiating download for #{url}"
    %{
      host: host,
      scheme: "ftp",
      port: port,
      userinfo: userinfo,
      path: path
    } = URI.parse(url)

    Logger.info "FTP start..."
    # TODO: do not start and stop at each request (this is just a PoC)
    :ftp.start()
    Logger.info "Connecting..."
    {:ok, pid} = :ftp.start_service(host: ~c(#{host}))
    try do

      if userinfo do
        Logger.info "Authenticating..."
        [user, pass] = userinfo |> String.split(":")
        :ftp.user(pid, ~c(#{user}), ~c(#{pass}))
      end

      # TODO: support streaming in memory to the caller and/or caching later
      target_filename = Path.basename(path)
      Logger.info("Downloading #{target_filename}...")
      :ok = :ftp.recv(pid, ~c(#{path}), target_filename)
      Logger.info "Success!"
      target_filename
    after
      Logger.info "Disconnecting..."
      :ftp.stop_service(pid)
      :ftp.stop()
    end
  end
end
