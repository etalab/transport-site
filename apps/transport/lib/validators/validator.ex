defmodule Transport.Validators.Validator do
  @moduledoc """
  A behavior for a validator. A validator must be able to:
  * validate
  * tell its name
  """

  @callback validate(any()) :: :ok | {:error, any()}
  @callback validator_name() :: binary()
end
