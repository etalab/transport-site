defmodule Transport.RamboLauncher do
  @moduledoc """
    A behavior for Rambo, with dynamic dispatching
  """
  @callback run(binary(), [binary()]) :: {:ok, binary()} | {:error, any()}

  def impl, do: Application.get_env(:transport, :rambo_impl)

  def run(binary_path, options), do: impl().run(binary_path, options)
end

defmodule Transport.Rambo do
  @moduledoc """
    Run an executable with Rambo
  """
  @behaviour Transport.RamboLauncher

  @impl Transport.RamboLauncher
  def run(binary_path, options) do
    # TO DO: make sure to have a command that we can run on any dev machine (with docker)
    # TO DO: make sure to "clear" the ENV before calling a binary
    # TO DO: make sure to "change working directory" to a specific working place
    case Rambo.run(binary_path, options) do
      {:ok, %Rambo{out: res}} -> {:ok, res}
      {:error, %Rambo{err: err_msg}} -> {:error, err_msg}
      {:error, _} = r -> r
    end
  end
end
