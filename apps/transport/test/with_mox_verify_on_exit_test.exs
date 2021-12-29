defmodule WithMoxVerifyOnExitTest do
  @moduledoc """
  Check that we did not forget to verify on exit when using Mox.
  """
  use ExUnit.Case

  test "If you use Mox, you verify on exit" do
    files =
      "../../apps/**/*_test.exs"
      |> Path.wildcard()
      |> Enum.filter(&potential_mox_issue_detected?/1)
      |> Enum.map(&Path.relative_to(&1, "../.."))

    assert files == []
  end

  def potential_mox_issue_detected?(file) do
    content = File.read!(file)
    use_mox = String.contains?(content, "import Mox")
    verify_on_exit = String.contains?(content, ":verify_on_exit!")
    use_mox and not verify_on_exit
  end
end
