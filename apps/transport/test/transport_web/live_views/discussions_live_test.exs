defmodule Transport.TransportWeb.DiscussionsLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "render some discussions", %{conn: conn} do
    dataset = insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate(), organization: "PAN_org")

    Datagouvfr.Client.Discussions.Mock |> expect(:get, 1, fn ^datagouv_id -> discussions() end)
    Datagouvfr.Client.Organization.Mock |> expect(:get, 1, fn "PAN_org" -> organization() end)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.DiscussionsLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id,
          "current_user" => %{"email" => "fc@tdg.fr"},
          "dataset" => dataset,
          "locale" => "fr"
        }
      )

    assert render(view) =~ "petite question"
    assert render(view) =~ "Le titre de la question"
    assert render(view) =~ "Francis Chabouis"
    assert render(view) =~ "07/06/2023"
  end

  test "renders even if data.gouv is down", %{conn: conn} do
    dataset = insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    # in case of request failure, the function returns an empty list.
    Datagouvfr.Client.Discussions.Mock |> expect(:get, 1, fn ^datagouv_id -> [] end)
    Datagouvfr.Client.Organization.Mock |> expect(:get, 1, fn _id -> {:error, "error reason"} end)

    assert {:ok, view, _html} =
             live_isolated(conn, TransportWeb.DiscussionsLive,
               session: %{
                 "dataset_datagouv_id" => datagouv_id,
                 "current_user" => %{"email" => "fc@tdg.fr"},
                 "dataset" => dataset,
                 "locale" => "fr"
               }
             )

    # we render the view to make sure the async call to data.gouv is done
    assert render(view) =~ ""
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
              "id" => "5e60d6668b4c410c429b8a4a",
              "last_name" => "Chabouis",
              "page" => "https://demo.data.gouv.fr/fr/users/francis-chabouis-1/",
              "slug" => "francis-chabouis-1",
              "uri" => "https://demo.data.gouv.fr/api/1/users/francis-chabouis-1/"
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

  defp organization() do
    {:ok, %{"members" => [%{"user" => %{"id" => "1"}}]}}
  end
end
