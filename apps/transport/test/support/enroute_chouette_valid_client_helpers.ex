defmodule Transport.Test.EnRouteChouetteValidClientHelpers do
  @moduledoc """
  This module defines helpers to setup a mock enRoute Chouette Valid client.
  """
  import Mox

  def expect_create_validation do
    validation_id = Ecto.UUID.generate()
    expect(Transport.EnRouteChouetteValidClient.Mock, :create_a_validation, fn _ -> validation_id end)
    validation_id
  end

  def expect_pending_validation(validation_id) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_a_validation, fn ^validation_id -> :pending end)
  end

  def expect_successful_validation(validation_id, elapsed) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_a_validation, fn ^validation_id ->
      {:successful, "http://localhost:9999/chouette-valid/#{validation_id}", elapsed}
    end)
  end

  def expect_failed_validation(validation_id, elapsed) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_a_validation, fn ^validation_id -> {:failed, elapsed} end)
  end

  def expect_get_messages(validation_id, result) do
    expect(Transport.EnRouteChouetteValidClient.Mock, :get_messages, fn ^validation_id ->
      {"http://localhost:9999/chouette-valid/#{validation_id}/messages", result}
    end)
  end
end
