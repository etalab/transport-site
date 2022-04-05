defmodule Mailjet.ClientTest do
  use ExUnit.Case
  import Mox
  import ExUnit.CaptureLog
  setup :verify_on_exit!

  test "sends email via the MailJet API" do
    Transport.HTTPoison.Mock
    |> expect(:post, fn url, body, headers, options ->
      assert url == "https://api.mailjet.com/v3.1/send"
      assert headers == nil
      assert options == [{:hackney, [basic_auth: {"TEST_MJ_APIKEY_PUBLIC", "TEST_MJ_APIKEY_PRIVATE"}]}]
      # see https://dev.mailjet.com/email/guides/send-api-v31/
      assert Jason.decode!(body) == %{
               "Messages" => [
                 %{
                   "From" => %{"Email" => "from@example.com", "Name" => "Test"},
                   "HtmlPart" => "<p>It is the HTML body</p>",
                   "ReplyTo" => %{"Email" => "reply@example.com"},
                   "Subject" => "Hello world",
                   "TextPart" => "This is the body",
                   "To" => [%{"Email" => "to@example.com"}]
                 }
               ]
             }

      {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}}
    end)

    {:ok, "{}"} =
      Mailjet.Client.send_mail(
        "Test",
        "from@example.com",
        "to@example.com",
        "reply@example.com",
        "Hello world",
        "This is the body",
        "<p>It is the HTML body</p>"
      )
  end
end
