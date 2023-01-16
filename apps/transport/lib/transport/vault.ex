defmodule Transport.Vault do
  @moduledoc """
  A vault, used by `cloak_ecto` to encrypt/decrypt
  https://hexdocs.pm/cloak_ecto/install.html#create-a-vault
  """
  use Cloak.Vault, otp_app: :transport

  # This value should be base64 encrypted
  # See https://github.com/danielberkompas/cloak#configuration
  @prod_config_env_name "CLOAK_KEY"

  @impl GenServer
  def init(config) do
    # See config recommendation
    # https://github.com/danielberkompas/cloak#configuration
    config =
      Keyword.put(config, :ciphers, default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V2", key: key(), iv_length: 12})

    {:ok, config}
  end

  defp key do
    case Application.fetch_env!(:transport, :app_env) do
      env when env in [:production, :staging] ->
        @prod_config_env_name
        |> System.fetch_env!()
        |> Base.decode64!()

      _ ->
        # A fake encryption key, suitable for dev/test
        "AhBXnRHXxioy+OBaZXP1dawhvhtNFwTzi9kh9QBkXuQ="
        |> Base.decode64!()
    end
  end
end
