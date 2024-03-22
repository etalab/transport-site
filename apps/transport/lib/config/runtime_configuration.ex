defmodule Transport.RuntimeConfiguration do
  defmodule SystemEnvProvider do
    @callback get_env(String.t()) :: String.t() | nil
    @callback get_env(String.t(), String.t()) :: String.t() | nil

    defmodule RealImpl do
      @behaviour SystemEnvProvider
      defdelegate get_env(key), to: System
      defdelegate get_env(key, default), to: System
    end

    def impl, do: RealImpl
  end

  def build_config(env_provider, config_env) do
    case config_env do
      :prod ->
        {
          env_provider.get_env("WORKER") || raise("expected the WORKER environment variable to be set"),
          env_provider.get_env("WEBSERVER") || raise("expected the WEBSERVER variable to be set")
        }

      :dev ->
        # By default in dev, the application will be both a worker and a webserver
        {
          env_provider.get_env("WORKER", "1"),
          env_provider.get_env("WEBSERVER", "1")
        }

      :test ->
        {
          "0",
          "0"
        }
    end
  end
end
