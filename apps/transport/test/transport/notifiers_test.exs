defmodule Transport.NotifiersTest do
  moduledoc("""
  This module is just there to run the doctests of the notifiers, which have been moved from other modules.
  """)

  use ExUnit.Case, async: true
  doctest Transport.UserNotifier, import: true
  doctest Transport.AdminNotifier, import: true
end
