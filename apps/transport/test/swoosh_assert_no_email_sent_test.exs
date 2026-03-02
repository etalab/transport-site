defmodule SwooshAssertNoEmailSent do
  @moduledoc """
  Check that we didn't send more emails when using Swoosh.
  """
  use ExUnit.Case, async: true

  test "if you verify emails sent, you assert_no_email_sent" do
    files =
      "../../apps/transport/test/**/*_test.exs"
      |> Path.wildcard()
      |> Enum.filter(&potential_issue_detected?/1)
      |> Enum.map(&Path.relative_to(&1, "../.."))

    assert files == []
  end

  def potential_issue_detected?(file) do
    content = File.read!(file)
    use_swoosh = String.contains?(content, "import Swoosh.TestAssertions")
    assert_no_email_sent = String.contains?(content, "on_exit(fn -> assert_no_email_sent() end)")
    use_swoosh and not assert_no_email_sent
  end
end
