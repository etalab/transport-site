defmodule Transport.Validators.Validator do
  @moduledoc """
  A behavior for a validator. A validator must be able to:
  * validate
  * tell its name
  """

  @callback validate(any()) :: :ok | {:error, any()}
  @callback validator_name() :: binary()
end

defmodule Transport.Validators.Dummy do
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate(_), do: :ok

  @impl Transport.Validators.Validator
  def validator_name, do: "dummy validator"
end
