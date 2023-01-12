defmodule Transport.Vault do
  use Cloak.Vault, otp_app: :transport

  @prod_config_env_name "CLOAK_KEY"

  @impl GenServer
  def init(config) do
    config = Keyword.put(config, :ciphers, default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key()})

    {:ok, config}
  end

  defp key do
    case Application.fetch_env!(:transport, :app_env) do
      env when env in [:production, :staging] ->
        @prod_config_env_name
        |> System.get_env()
        |> Base.decode64!()

      _ ->
        # A fake encryption, suitable for dev/test
        "AhBXnRHXxioy+OBaZXP1dawhvhtNFwTzi9kh9QBkXuQ="
        |> Base.decode64!()
    end
  end
end
