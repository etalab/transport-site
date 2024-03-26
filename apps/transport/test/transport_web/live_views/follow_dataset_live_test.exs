defmodule Transport.TransportWeb.FollowDatasetLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "when current_user is nil", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "dataset_id" => insert(:dataset).id,
          "current_user" => nil
        }
      )

    assert_renders_empty_div(view)
  end

  test "when current_user is a producer of the dataset", %{conn: conn} do
    organization = build(:organization)
    producer = insert_contact(%{datagouv_user_id: Ecto.UUID.generate(), organizations: [Map.from_struct(organization)]})
    dataset = insert(:dataset, organization_id: organization.id)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "dataset_id" => dataset.id,
          "current_user" => %{"id" => producer.datagouv_user_id}
        }
      )

    assert_renders_empty_div(view)
  end

  test "follows the dataset, clicking the heart icon", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    insert(:dataset_follower, contact_id: contact.id, dataset_id: dataset.id, source: :datagouv)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "dataset_id" => dataset.id,
          "current_user" => %{"id" => contact.datagouv_user_id}
        }
      )

    assert_renders_red_heart(view)
    assert [%DB.DatasetFollower{dataset_id: ^dataset_id, contact_id: ^contact_id}] = DB.DatasetFollower |> DB.Repo.all()

    # Clicking the heart icon
    view |> element("div i") |> render_click()

    assert_renders_grey_heart(view)
    assert [] == DB.DatasetFollower |> DB.Repo.all()
  end

  test "does not follow the dataset, clicking the heart icon", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    %DB.Contact{id: contact_id} = contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.FollowDatasetLive,
        session: %{
          "dataset_id" => dataset.id,
          "current_user" => %{"id" => contact.datagouv_user_id}
        }
      )

    assert_renders_grey_heart(view)

    # Clicking the heart icon
    view |> element("div i") |> render_click()

    assert_renders_red_heart(view)

    assert [%DB.DatasetFollower{dataset_id: ^dataset_id, contact_id: ^contact_id, source: :follow_button}] =
             DB.DatasetFollower |> DB.Repo.all()
  end

  defp assert_renders_empty_div(%Phoenix.LiveViewTest.View{} = view) do
    assert [{"div", _, []}] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_grey_heart(%Phoenix.LiveViewTest.View{} = view) do
    assert [
             {"div", _,
              [
                {"div", [{"class", "follow-dataset-icon"}],
                 [{"i", [{"class", "fa fa-heart fa-2x icon---animated-heart"}, {"phx-click", "toggle"}], []}]}
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end

  defp assert_renders_red_heart(%Phoenix.LiveViewTest.View{} = view) do
    assert [
             {"div", _,
              [
                {"div", [{"class", "follow-dataset-icon"}],
                 [{"i", [{"class", "fa fa-heart fa-2x icon---animated-heart active"}, {"phx-click", "toggle"}], []}]}
              ]}
           ] = view |> render() |> Floki.parse_document!()
  end
end
