defmodule TransportWeb.Live.FollowDatasetLiveTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "when user is logged out", %{conn: conn} do
    dataset = insert(:dataset)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "locale" => "fr",
          "dataset_id" => dataset.id,
          "current_user" => nil
        }
      )

    assert_renders_logged_out_div(view, with_banner: false)

    # Clicking the heart icon
    view |> element("div i") |> render_click()

    assert_renders_logged_out_div(view, with_banner: true)
  end

  test "when current_user is a producer of the dataset", %{conn: conn} do
    organization = build(:organization)
    producer = insert_contact(%{datagouv_user_id: Ecto.UUID.generate(), organizations: [Map.from_struct(organization)]})
    dataset = insert(:dataset, organization_id: organization.id)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "locale" => "fr",
          "dataset_id" => dataset.id,
          "current_user" => %{"id" => producer.datagouv_user_id}
        }
      )

    assert_renders_manage_settings_div(view)
  end

  test "follows the dataset", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :datagouv)

    notification_subscription =
      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: dataset.id,
        source: :user,
        role: :reuser,
        reason: :expiration
      )

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "locale" => "fr",
          "dataset_id" => dataset.id,
          "current_user" => %{"id" => contact.datagouv_user_id}
        }
      )

    assert [notification_subscription] == DB.NotificationSubscription |> DB.Repo.all()
    assert_renders_red_heart(view, with_banner: false)
    assert [%DB.DatasetFollower{dataset_id: ^dataset_id, contact_id: ^contact_id}] = DB.DatasetFollower |> DB.Repo.all()
  end

  test "does not follow the dataset, clicking the heart icon", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "locale" => "fr",
          "dataset_id" => dataset.id,
          "current_user" => %{"id" => contact.datagouv_user_id}
        }
      )

    assert_renders_grey_heart(view)

    assert [] == DB.NotificationSubscription |> DB.Repo.all()

    # Clicking the heart icon
    view |> element("div i") |> render_click()

    assert_renders_red_heart(view, with_banner: true)

    # Dataset is now being followed
    assert [%DB.DatasetFollower{dataset_id: ^dataset_id, contact_id: ^contact_id, source: :follow_button}] =
             DB.DatasetFollower |> DB.Repo.all()

    # Enqueued a job to promote the reuser space
    assert [%Oban.Job{worker: "Transport.Jobs.PromoteReuserSpaceJob", args: %{"contact_id" => ^contact_id}}] =
             all_enqueued()

    # The user is subscribed to all reasons
    assert [
             %DB.NotificationSubscription{
               reason: :daily_new_comments,
               source: :user,
               role: :reuser,
               contact_id: ^contact_id,
               dataset_id: nil
             },
             %DB.NotificationSubscription{
               reason: :dataset_with_error,
               source: :user,
               role: :reuser,
               contact_id: ^contact_id,
               dataset_id: ^dataset_id
             },
             %DB.NotificationSubscription{
               reason: :expiration,
               source: :user,
               role: :reuser,
               contact_id: ^contact_id,
               dataset_id: ^dataset_id
             },
             %DB.NotificationSubscription{
               reason: :resource_unavailable,
               source: :user,
               role: :reuser,
               contact_id: ^contact_id,
               dataset_id: ^dataset_id
             },
             %DB.NotificationSubscription{
               reason: :resources_changed,
               source: :user,
               role: :reuser,
               contact_id: ^contact_id,
               dataset_id: ^dataset_id
             }
           ] =
             DB.NotificationSubscription
             |> DB.Repo.all()
             |> Enum.sort_by(fn %DB.NotificationSubscription{reason: reason} -> reason end)
  end

  test "does not enqueue a job if the user already follows a dataset", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    %DB.Dataset{id: other_dataset_id} = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    insert(:dataset_follower, contact_id: contact_id, dataset_id: other_dataset_id, source: :follow_button)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "locale" => "fr",
          "dataset_id" => dataset_id,
          "current_user" => %{"id" => contact.datagouv_user_id}
        }
      )

    assert_renders_grey_heart(view)

    # Clicking the heart icon
    view |> element("div i") |> render_click()

    assert_renders_red_heart(view, with_banner: true)

    assert [] == all_enqueued()
  end

  test "content is translated", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "locale" => "en",
          "dataset_id" => dataset_id,
          "current_user" => %{"id" => datagouv_user_id}
        }
      )

    assert "Follow this dataset" ==
             view |> render() |> Floki.parse_document!() |> Floki.find(".tooltiptext") |> Floki.text()
  end

  describe "maybe_promote_reuser_space" do
    test "enqueues a job if the user already follows a dataset but not through the button" do
      %DB.Dataset{id: dataset_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :datagouv)

      TransportWeb.Live.FollowDatasetLive.maybe_promote_reuser_space(contact)

      assert [%Oban.Job{worker: "Transport.Jobs.PromoteReuserSpaceJob", args: %{"contact_id" => ^contact_id}}] =
               all_enqueued()
    end

    test "does not enqueue a job if the user already follows a dataset through the button" do
      %DB.Dataset{id: dataset_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :follow_button)

      TransportWeb.Live.FollowDatasetLive.maybe_promote_reuser_space(contact)

      assert [] == all_enqueued()
    end
  end

  describe "maybe_subscribe_to_daily_new_comments" do
    test "user not subscribed to daily comments, 0 subscriptions" do
      %DB.Contact{id: contact_id} = contact = insert_contact()
      TransportWeb.Live.FollowDatasetLive.maybe_subscribe_to_daily_new_comments(contact)

      assert [
               %DB.NotificationSubscription{
                 reason: :daily_new_comments,
                 source: :user,
                 role: :reuser,
                 contact_id: ^contact_id,
                 dataset_id: nil
               }
             ] = DB.NotificationSubscription |> DB.Repo.all()
    end

    test "user is already subscribed to daily comments" do
      %DB.Contact{id: contact_id} = contact = insert_contact()

      notification_subscription =
        insert(:notification_subscription,
          reason: :daily_new_comments,
          role: :reuser,
          source: :user,
          contact_id: contact_id
        )

      TransportWeb.Live.FollowDatasetLive.maybe_subscribe_to_daily_new_comments(contact)
      assert [notification_subscription] == DB.NotificationSubscription |> DB.Repo.all()
    end

    test "user not subscribed to daily comments, an existing subscription" do
      %DB.Contact{id: contact_id} = contact = insert_contact()
      %DB.Dataset{id: dataset_id} = insert(:dataset)

      notification_subscription =
        insert(:notification_subscription,
          reason: :expiration,
          role: :reuser,
          source: :user,
          contact_id: contact_id,
          dataset_id: dataset_id
        )

      TransportWeb.Live.FollowDatasetLive.maybe_subscribe_to_daily_new_comments(contact)

      assert [notification_subscription] == DB.NotificationSubscription |> DB.Repo.all()
    end
  end

  defp assert_renders_logged_out_div(%Phoenix.LiveViewTest.View{} = view, with_banner: true) do
    infos_url = page_path(TransportWeb.Endpoint, :infos_reutilisateurs)

    assert [
             {"div", _,
              [
                {"div", [{"class", "follow-dataset-icon"}],
                 [
                   {"i", [{"class", "fa fa-heart fa-2x icon---animated-heart"}, {"phx-click", "nudge_signup"}], []},
                   {
                     "p",
                     [{"class", "notification active"}],
                     [
                       {"a", [{"href", ^infos_url}, {"target", "_blank"}], ["Inscrivez-vous ou connectez-vous"]},
                       _
                     ]
                   }
                 ]}
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_logged_out_div(%Phoenix.LiveViewTest.View{} = view, with_banner: false) do
    assert [
             {"div", _,
              [
                {"div", [{"class", "follow-dataset-icon"}],
                 [
                   {"i", [{"class", "fa fa-heart fa-2x icon---animated-heart"}, {"phx-click", "nudge_signup"}], []}
                 ]}
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_manage_settings_div(%Phoenix.LiveViewTest.View{} = view) do
    assert [
             {"div", _,
              [
                {"div", [{"class", "follow-dataset-icon"}],
                 [
                   {"div", [{"class", "tooltip"}],
                    [
                      {"a", [{"href", "/espace_producteur?utm_campaign=follow_dataset_heart"}, {"target", "_blank"}],
                       [{"i", [{"class", "fa fa-heart fa-2x producer"}], []}]},
                      {"span", [{"class", "tooltiptext left"}], ["Gérez votre jeu de données"]}
                    ]}
                 ]}
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_grey_heart(%Phoenix.LiveViewTest.View{} = view) do
    assert [
             {"div", _,
              [
                {
                  "div",
                  [{"class", "follow-dataset-icon"}],
                  [
                    {
                      "div",
                      [{"class", "tooltip"}],
                      [
                        {"i", [{"class", "fa fa-heart fa-2x icon---animated-heart"}, {"phx-click", "follow"}], []},
                        {"span", [{"class", "tooltiptext left"}], ["Suivre ce jeu de données"]}
                      ]
                    }
                  ]
                }
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_red_heart(%Phoenix.LiveViewTest.View{} = view, with_banner: true) do
    assert [
             {"div", _,
              [
                {
                  "div",
                  [{"class", "follow-dataset-icon"}],
                  [
                    {
                      "div",
                      [{"class", "tooltip"}],
                      [
                        {"a",
                         [{"href", "/espace_reutilisateur?utm_campaign=follow_dataset_heart"}, {"target", "_blank"}],
                         [{"i", [{"class", "fa fa-heart fa-2x icon---animated-heart active"}], []}]},
                        {"span", [{"class", "tooltiptext left"}], ["Gérez les services liés à ce jeu de données"]}
                      ]
                    },
                    {
                      "p",
                      [{"class", "notification active"}],
                      [
                        "\n    Jeu de données ajouté à vos favoris ! Personnalisez vos préférences depuis votre ",
                        {"a",
                         [{"href", "/espace_reutilisateur?utm_campaign=follow_dataset_heart"}, {"target", "_blank"}],
                         ["espace réutilisateur"]},
                        ".\n  "
                      ]
                    }
                  ]
                }
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_red_heart(%Phoenix.LiveViewTest.View{} = view, with_banner: false) do
    assert [
             {"div", _,
              [
                {
                  "div",
                  [{"class", "follow-dataset-icon"}],
                  [
                    {
                      "div",
                      [{"class", "tooltip"}],
                      [
                        {"a",
                         [{"href", "/espace_reutilisateur?utm_campaign=follow_dataset_heart"}, {"target", "_blank"}],
                         [{"i", [{"class", "fa fa-heart fa-2x icon---animated-heart active"}], []}]},
                        {"span", [{"class", "tooltiptext left"}], ["Gérez les services liés à ce jeu de données"]}
                      ]
                    }
                  ]
                }
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end
end
