defmodule TransportWeb.UserFacingCase do
  @moduledoc """
  This module defines the test case to be used by
  integration and solution (acceptance, e2e) tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Hound.Helpers
      hound_session()
    end
  end
end
