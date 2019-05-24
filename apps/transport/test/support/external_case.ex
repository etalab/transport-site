defmodule TransportWeb.ExternalCase do
  @moduledoc """
  This module defines the test case to be used by
  test that require to mock external API calls.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney, options: [clear_mock: true]
      import Plug.Test
    end
  end
end
