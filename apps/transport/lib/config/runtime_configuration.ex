defmodule Transport.RuntimeConfiguration do
  @moduledoc """
  A module allowing us to bring some structure & testing to what is happening
  inside `runtime.exs`.
  """

  defmodule SystemEnvProvider do
    @moduledoc """
    A behaviour wrapping the sub-part of `System.get_env`  calls required by
    the current `runtime.exs` configuration. We define this boundary/interface
    to help stub the environment variables during tests, and ensure we can get
    robust well-tested production configuration.
    """

    @callback get_env(String.t()) :: String.t() | nil
    @callback get_env(String.t(), String.t()) :: String.t() | nil

    defmodule RealImpl do
      @moduledoc """
      The real implementation of the `SystemEnvProvider` behaviour, delegating
      calls to `System.get_env` etc.
      """

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
