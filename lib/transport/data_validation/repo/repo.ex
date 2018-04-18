defmodule Transport.DataValidation.Repo do
  @moduledoc """
  A repository behaviour to validate, store and retrieve dataset validations.

  Whether there is a database, and API or a mock behind, the public signature
  should be consistent.
  """

  @typedoc """
  A query is an idempotent request.
  """
  @type query :: struct

  @typedoc """
  A command is a request with side effects.
  """
  @type command :: struct

  @typedoc """
  An action can be either a query or a command.
  """
  @type action :: query | command

  @typedoc """
  A model is a domain model.
  """
  @type model :: struct

  @callback execute(action :: action) ::
              {:ok, nil} | {:ok, model} | {:ok, [model]} | {:error, any}
end
