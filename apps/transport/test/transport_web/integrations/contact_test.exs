defmodule TransportWeb.Integration.ContactTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [], async: false
  use TransportWeb.UserFacingCase

  @tag :integration
  test "add a button to contact the team and ask for help" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    :class
    |> find_element("mail__button")
    |> find_within_element(:class, "icon--envelope")
    |> assert
  end

  @tag :integration
  test "Post contact form with honey pot filled", %{conn: conn} do
    conn
    |> post("/send_mail", email: "spammer@internet.com", name: "John Doe")
    |> get_flash(:info)
    # only spammers get a fox emoji in their flash message
    |> Kernel.=~("🦊")
    |> assert
  end

  @tag :integration
  test "Post contact form without honey pot", %{conn: conn} do
    conn
    |> post("/send_mail",
      email: "human@user.fr",
      topic: "question",
      demande: "where is my dataset?"
    )
    |> get_flash(:info)
    |> case do
      nil -> assert true
      msg -> refute msg =~ "🦊"
    end
  end
end
