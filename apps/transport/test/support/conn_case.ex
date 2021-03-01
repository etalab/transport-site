defmodule TransportWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate
  alias Phoenix.ConnTest

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      # NOTE: init_test_session delegates to Plug.Test as seen here,
      # https://github.com/phoenixframework/phoenix/blob/v1.5.7/lib/phoenix/test/conn_test.ex#L253
      # which is also imported, hence generating a compilation error.
      # This is due to how we configured the various "cases" I believe, and we'll have to clean that up.
      import Phoenix.ConnTest, except: [init_test_session: 2]
      import TransportWeb.Router.Helpers

      # The default endpoint for testing
      @endpoint TransportWeb.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: ConnTest.build_conn()}
  end
end
