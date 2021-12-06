defmodule Unlock.HTTP.FinchImplTest do
  use ExUnit.Case, async: true
  import Mox
  alias Unlock.HTTP.{FinchImpl, Response}

  setup :verify_on_exit!

  describe "get!" do
    test "without a redirection" do
      assert %Response{
               status: 301,
               body: _body,
               headers: _headers
             } = FinchImpl.get!("http://lemonde.fr", [])
    end

    test "with a redirection" do
      assert %Response{
               status: 200,
               body: _body,
               headers: _headers
             } = FinchImpl.get!("http://lemonde.fr", [], follow_redirect: true)
    end
  end
end
