defmodule Transport.Validators.Validator do
  @moduledoc """
  A behavior for a validator. A validator must be able to:
  * validate
  * tell its name
  """

  @callback validate_and_save(any()) :: :ok | {:error, any()}
  @callback validator_name() :: binary()
end

defmodule Transport.Validators.Dummy do
  @moduledoc """
  dummy validator used for testing
  """
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(_) do
    send(self(), :validate!)
    :ok
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "dummy validator"
end
