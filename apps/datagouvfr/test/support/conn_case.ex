defmodule DataGouvFr.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate
  alias Phoenix.ConnTest

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest, except: [init_test_session: 2]

      # The default endpoint for testing
      @endpoint DataGouvFr.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: ConnTest.build_conn()}
  end
end
