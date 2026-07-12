defmodule TransportWeb.ExternalCase do
  @moduledoc """
  Test case for tests that exercise external API calls (now mocked via Mox).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Test
    end
  end
end
