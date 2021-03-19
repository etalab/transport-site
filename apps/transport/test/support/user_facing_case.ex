defmodule TransportWeb.UserFacingCase do
  @moduledoc """
  This module defines the test case to be used by
  integration (acceptance, e2e) tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Hound.Helpers
      # NOTE: use a deterministic window size to make sure we do not meet failures
      # due to find_element needing "below the fold" search
      # See https://github.com/HashNuke/hound/issues/186
      hound_session(driver: %{chromeOptions: %{args: ["--window-size=1024,768"]}})
    end
  end
end
