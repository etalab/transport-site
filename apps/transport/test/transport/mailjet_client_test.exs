defmodule Mailjet.ClientTest do
  use ExUnit.Case

  test "it works" do
    Mailjet.Client.send_mail(
      "Test",
      "from@example.com",
      "to@example.com",
      "reply@example.com",
      "Hello world",
      "This is the body",
      "<p>It is the HTML body</p>",
      false
    )
  end
end
