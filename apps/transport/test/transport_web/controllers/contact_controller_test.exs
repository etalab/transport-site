defmodule TransportWeb.ContactControllerTest do
  use TransportWeb.ConnCase, async: false

  test "Post contact form with honey pot filled", %{conn: conn} do
    conn
    |> post(contact_path(conn, :send_mail, %{email: "spammer@internet.com", name: "John Doe"}))
    |> get_flash(:info)
    # only spammers get a fox emoji in their flash message
    |> Kernel.=~("🦊")
    |> assert
  end

  test "Post contact form without honey pot", %{conn: conn} do
    conn
    |> post(
      contact_path(conn, :send_mail, %{email: "human@user.fr", topic: "question", demande: "where is my dataset?"})
    )
    |> get_flash(:info)
    |> case do
      nil -> assert true
      msg -> refute msg =~ "🦊"
    end
  end
end
