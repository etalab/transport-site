defmodule Shared.Validation.Validator do
  @moduledoc """
  Describe the behaviour of a resource validator.
  """

  # @doc """
  # Validate the given resource.
  # """
  # # @callback validate(binary()) :: {:ok, map()} | {:error, binary()}

  @doc """
  Validate the resource from the given URL.
  """
  @callback validate_from_url(binary()) :: {:ok, map()} | {:error, binary()}
end
