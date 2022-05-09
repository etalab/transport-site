defmodule Mailjet.ClientTest do
  # not async because we use config change
  use ExUnit.Case, async: false
  import Mox
  setup :verify_on_exit!

  test "sends email via the MailJet API" do
    Transport.HTTPoison.Mock
    |> expect(:post, fn url, body, headers, options ->
      assert url == "https://api.mailjet.com/v3.1/send"
      assert headers == []
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

    verify!(Transport.HTTPoison.Mock)
  end

  test "goes through hackney without pain (integration style)" do
    assert Mailjet.Client.mailjet_url == "https://api.mailjet.com/v3.1/send"

    bypass = Bypass.open()

    # here we just ensure something has reached the server, to go through a real
    # hackney path ; the payload itself is tested in the other test
    Bypass.expect(bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "")
    end)

    # reconfigure the app to tap into bypass server & stop using mocking
    config = Application.fetch_env!(:transport, Mailjet.Client)
    AppConfigHelper.change_app_config_temporarily(:transport, Mailjet.Client, Keyword.merge(config, mailjet_url: "http://localhost:#{bypass.port}"))
    AppConfigHelper.change_app_config_temporarily(:transport, :email_sender_impl, Mailjet.Client)
    AppConfigHelper.change_app_config_temporarily(:transport, :httpoison_impl, HTTPoison)

    assert Mailjet.Client.mailjet_url == "http://localhost:#{bypass.port}"

    Mailjet.Client.send_mail("FROM", "from@example.com", "to@example.com", "reply_to@example.com", "the subject", "plain text body", "html body")
  end
end
