defmodule Transport.Scheduler do
  @moduledoc """
  This made to launch schedule tasks
  """

  use Quantum.Scheduler,
    otp_app: :transport
end
