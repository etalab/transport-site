defmodule Transport.Test.EnRouteChouetteValidClientHelpers do
  @moduledoc """
  This module defines helpers to setup a mock enRoute Chouette Valid client.
  """

  import Mox

  @behaviour Transport.EnRouteChouetteValidClient.Wrapper

  ## Expectation helpers

  @doc """
  Expect a call to `create_a_validation/3` with the given ruleset.
  Returns a generated validation_id that will be returned by the mock.
  """
  def expect_create_validation(ruleset) do
    validation_id = with_running_validation()

    expect(Transport.EnRouteChouetteValidClient.Mock, :create_a_validation, fn _, ^ruleset, _xsd_version ->
      validation_id
    end)

    validation_id
  end

  @doc """
  Expect a call to get_a_validation for the given validation_id to return :pending.
  """
  def expect_pending_validation(validation_id) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_a_validation, fn ^validation_id -> :pending end)
    validation_id
  end

  @doc """
  Expect a call to get_a_validation for the given validation_id to return successful.
  """
  def expect_successful_validation(validation_id, elapsed) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_a_validation, fn ^validation_id ->
      {:successful, "http://localhost:9999/chouette-valid/#{validation_id}", elapsed}
    end)

    validation_id
  end

  @doc """
  Expect a call to get_a_validation for the given validation_id to return failed.
  """
  def expect_failed_validation(validation_id, elapsed) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_a_validation, fn ^validation_id -> {:failed, elapsed} end)

    validation_id
  end

  @doc """
  Expect a call to get_messages for the given validation_id.
  """
  def expect_get_messages(validation_id, result) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_messages, fn ^validation_id ->
      {"http://localhost:9999/chouette-valid/#{validation_id}/messages", result}
    end)

    validation_id
  end

  def with_running_validation, do: Ecto.UUID.generate()

  ## Mock implementations - required by Mox.stub_with/2

  @impl Transport.EnRouteChouetteValidClient.Wrapper
  def create_a_validation(_filepath, ruleset, _xsd_version) do
    # This should never be called directly; use expect_create_validation/1 instead.
    raise "No expectation set for create_a_validation(#{inspect(ruleset)}). Call expect_create_validation/1 in your test setup."
  end

  @impl Transport.EnRouteChouetteValidClient.Wrapper
  def get_a_validation(validation_id) do
    # This should never be called directly; use expect_*_validation/2 instead.
    raise "No expectation set for get_a_validation(#{inspect(validation_id)}). Call an expect_*_validation helper in your test setup."
  end

  @impl Transport.EnRouteChouetteValidClient.Wrapper
  def get_messages(validation_id) do
    # This should never be called directly; use expect_get_messages/2 instead.
    raise "No expectation set for get_messages(#{inspect(validation_id)}). Call expect_get_messages/2 in your test setup."
  end
end
