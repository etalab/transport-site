defmodule Transport.TransportWeb.DiscussionsLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox

  @admin_datagouv_id "5e60d6668b4c410c429b8a4a"

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    %{admin_org: insert(:organization, name: "Point d'Accès National transport.data.gouv.fr")}
  end

  test "render some discussions", %{conn: conn, admin_org: admin_org} do
    insert_contact(%{datagouv_user_id: @admin_datagouv_id, organizations: [Map.from_struct(admin_org)]})

    dataset =
      insert(:dataset,
        datagouv_id: datagouv_id = Ecto.UUID.generate(),
        organization_id: organization_id = Ecto.UUID.generate()
      )

    Datagouvfr.Client.Discussions.Mock |> expect(:get, 1, fn ^datagouv_id -> discussions() end)

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, 1, fn ^organization_id, [restrict_fields: true] -> organization() end)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.DiscussionsLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id,
          "current_user" => %{"email" => "fc@tdg.fr"},
          "dataset" => dataset,
          "locale" => "fr",
          "csp_nonce_value" => Ecto.UUID.generate()
        }
      )

    parsed_content = view |> render() |> Floki.parse_document!()

    discussion_title_text =
      parsed_content |> Floki.find(".discussion-title h4") |> Floki.text()

    [question_comment, answer_comment] = Floki.find(parsed_content, ".discussion-comment")
    question_comment_text = Floki.text(question_comment)

    assert discussion_title_text =~ "Le titre de la question"
    assert question_comment_text =~ "petite question"
    assert question_comment_text =~ "Francis Chabouis"
    assert question_comment_text =~ "07/06/2023"
    refute question_comment_text =~ "Producteur de la donnée"

    # This user is a member of transport.data.gouv.fr
    assert [@admin_datagouv_id] == DB.Contact.admin_datagouv_ids()

    assert question_comment |> Floki.find(".label.label--role") |> Floki.text() |> String.trim() ==
             "transport.data.gouv.fr"

    assert question_comment |> Floki.find("img") |> Floki.attribute("alt") == ["Francis Chabouis"]

    # Producer badge
    assert answer_comment |> Floki.find(".label.label--role") |> Floki.text() |> String.trim() =~
             "Producteur de la donnée"

    assert answer_comment |> Floki.find("img") |> Floki.attribute("src") == [
             "https://demo-static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png"
           ]
  end

  test "renders even if data.gouv is down", %{conn: conn} do
    dataset =
      insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate(), organization_id: org_id = Ecto.UUID.generate())

    # in case of request failure, the function returns an empty list.
    Datagouvfr.Client.Discussions.Mock |> expect(:get, 1, fn ^datagouv_id -> [] end)
    Datagouvfr.Client.Organization.Mock |> expect(:get, 1, fn ^org_id, _opts -> {:error, "error reason"} end)

    assert {:ok, view, _html} =
             live_isolated(conn, TransportWeb.DiscussionsLive,
               session: %{
                 "dataset_datagouv_id" => datagouv_id,
                 "current_user" => %{"email" => "fc@tdg.fr"},
                 "dataset" => dataset,
                 "locale" => "fr",
                 "csp_nonce_value" => Ecto.UUID.generate()
               }
             )

    # we render the view to make sure the async call to data.gouv is done
    assert render(view) =~ ""
  end

  test "answer and answer and close buttons", %{conn: conn} do
    dataset =
      insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate(), organization_id: org_id = Ecto.UUID.generate())

    Datagouvfr.Client.Discussions.Mock |> expect(:get, 2, fn ^datagouv_id -> discussions() end)
    Datagouvfr.Client.Organization.Mock |> expect(:get, 2, fn ^org_id, [restrict_fields: true] -> organization() end)

    # When the current user *IS NOT* a member of the dataset organization
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.DiscussionsLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id,
          "current_user" => %{"email" => "fc@tdg.fr"},
          "dataset" => dataset,
          "locale" => "fr",
          "csp_nonce_value" => Ecto.UUID.generate()
        }
      )

    parsed_content = view |> render() |> Floki.parse_document!()
    assert "Répondre" == parsed_content |> Floki.find(".discussion-form button") |> Floki.text() |> String.trim()

    # When the current user *IS* a member of the dataset organization
    user_id = organization() |> elem(1) |> Map.fetch!("members") |> hd() |> get_in(["user", "id"])

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.DiscussionsLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id,
          "current_user" => %{"email" => "fc@tdg.fr", "id" => user_id},
          "dataset" => dataset,
          "locale" => "fr",
          "csp_nonce_value" => Ecto.UUID.generate()
        }
      )

    # Two buttons: answer + answer and close
    assert [
             {"button", [{"class", "button"}, {"name", "anwser"}, {"type", "submit"}], [anwser_text]},
             {"button", [{"class", "button secondary"}, {"name", "answer_and_close"}, {"type", "submit"}],
              [answer_and_close_text]}
           ] = view |> render() |> Floki.parse_document!() |> Floki.find(".discussion-form button")

    assert ["Répondre", "Répondre et clore"] == Enum.map([anwser_text, answer_and_close_text], &String.trim/1)
  end

  test "the counter reacts to broadcasted messages", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.CountDiscussionsLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id = Ecto.UUID.generate()
        }
      )

    refute render(view) =~ "("

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_discussions_count:bad_dataset_id",
      {:count, 10}
    )

    refute render(view) =~ "("

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_discussions_count:#{datagouv_id}",
      {:count, 10}
    )

    assert render(view) =~ "(10)"
  end

  test "a closed discussion should be displayed as closed" do
    discussion = %{"closed" => "2021-09-10T16:14:53.091000+00:00"}
    assert TransportWeb.DiscussionsLive.discussion_should_be_closed?(discussion)
  end

  test "a discussion with an old discussion should be displayed as closed" do
    discussion = %{
      "closed" => nil,
      "discussion" => [
        %{
          "posted_on" => iso8601_string_x_months_ago(3)
        },
        %{
          "posted_on" => iso8601_string_x_months_ago(4)
        },
        %{
          "posted_on" => iso8601_string_x_months_ago(5)
        }
      ]
    }

    assert TransportWeb.DiscussionsLive.discussion_should_be_closed?(discussion)
  end

  test "a discussion with a newer discussion should not be displayed as closed" do
    discussion = %{
      "closed" => nil,
      "discussion" => [
        %{
          "posted_on" => iso8601_string_x_months_ago(1)
        },
        %{
          "posted_on" => iso8601_string_x_months_ago(4)
        },
        %{
          "posted_on" => iso8601_string_x_months_ago(5)
        }
      ]
    }

    refute TransportWeb.DiscussionsLive.discussion_should_be_closed?(discussion)
  end

  defp iso8601_string_x_months_ago(x) do
    DateTime.utc_now() |> Timex.shift(months: -x) |> DateTime.to_iso8601()
  end

  defp discussions do
    [
      %{
        "class" => "Discussion",
        "closed" => nil,
        "closed_by" => nil,
        "created" => "2023-06-07T14:59:48.310000+00:00",
        "discussion" => [
          %{
            "content" => "petite question",
            "posted_by" => %{
              "avatar" => "https://demo-static.data.gouv.fr/avatars/66/831b849f1c454683bbc9253c5ee191-original.png",
              "avatar_thumbnail" =>
                "https://demo-static.data.gouv.fr/avatars/66/831b849f1c454683bbc9253c5ee191-500.png",
              "class" => "User",
              "first_name" => "Francis",
              "id" => @admin_datagouv_id,
              "last_name" => "Chabouis",
              "page" => "https://demo.data.gouv.fr/fr/users/francis-chabouis-1/",
              "slug" => "francis-chabouis-1",
              "uri" => "https://demo.data.gouv.fr/api/1/users/francis-chabouis-1/"
            },
            "posted_on" => "2023-06-07T14:59:48.310000+00:00"
          },
          %{
            "content" => "pouvez-vous répéter la question ?",
            "posted_by" => %{
              "avatar" => nil,
              "avatar_thumbnail" => nil,
              "class" => "User",
              "first_name" => "Vincent",
              "id" => "649ad29b9a7af3d61ded5785",
              "last_name" => "Degove",
              "page" => "https://demo.data.gouv.fr/fr/users/vincent-degove-1/",
              "slug" => "vincent-degove-1",
              "uri" => "https://demo.data.gouv.fr/api/1/users/vincent-degove-1/"
            },
            "posted_on" => "2023-06-07T14:59:48.310000+00:00"
          }
        ],
        "extras" => %{},
        "id" => "64809b64d0b8608165867d6f",
        "subject" => %{"class" => "Dataset", "id" => "60a37b7f303fdf4f2654b73d"},
        "title" => "Le titre de la question",
        "url" => "https://demo.data.gouv.fr/api/1/discussions/64809b64d0b8608165867d6f/",
        "user" => %{
          "avatar" => "https://demo-static.data.gouv.fr/avatars/66/831b849f1c454683bbc9253c5ee191-original.png",
          "avatar_thumbnail" => "https://demo-static.data.gouv.fr/avatars/66/831b849f1c454683bbc9253c5ee191-500.png",
          "class" => "User",
          "first_name" => "Francis",
          "id" => "5e60d6668b4c410c429b8a4a",
          "last_name" => "Chabouis",
          "page" => "https://demo.data.gouv.fr/fr/users/francis-chabouis-1/",
          "slug" => "francis-chabouis-1",
          "uri" => "https://demo.data.gouv.fr/api/1/users/francis-chabouis-1/"
        }
      }
    ]
  end

  defp organization do
    {:ok,
     %{
       "logo_thumbnail" => "https://demo-static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
       "members" => [%{"user" => %{"id" => "649ad29b9a7af3d61ded5785"}}]
     }}
  end
end
