defmodule DB.UserFeedbackTest do
  use ExUnit.Case, async: true
  import Ecto.Query
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save and read a feedback with encrypted email" do
    %DB.UserFeedback{}
    |> DB.UserFeedback.changeset(sample_feedback_args())
    |> DB.Repo.insert()

    expected_email = "malotru@example.com"

    assert %DB.UserFeedback{email: ^expected_email, explanation: "Awesome map!"} =
             DB.UserFeedback |> Ecto.Query.last() |> DB.Repo.one!()

    # Cannot get rows by using the email, because values are encrypted
    refute DB.UserFeedback |> where([f], f.email == ^expected_email) |> DB.Repo.exists?()
  end

  test "can be associated with an existing contact" do
    %DB.Contact{datagouv_user_id: user_id} = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    {:ok, feedback} =
      %DB.UserFeedback{}
      |> DB.UserFeedback.changeset(sample_feedback_args())
      |> DB.UserFeedback.assoc_contact_from_user_id(user_id)
      |> DB.Repo.insert()

    feedback_contact = DB.Repo.preload(feedback, :contact) |> Map.get(:contact)

    assert user_id == feedback_contact.datagouv_user_id
  end

  test "can be saved even without a user_id" do
    {:ok, feedback} =
      %DB.UserFeedback{}
      |> DB.UserFeedback.changeset(sample_feedback_args())
      |> DB.UserFeedback.assoc_contact_from_user_id(nil)
      |> DB.Repo.insert()

    assert is_nil(feedback.contact_id)
  end

  defp sample_feedback_args do
    %{
      rating: :like,
      explanation: "<love>Awesome map!</love>",
      feature: :gtfs_stops,
      email: "Malotru@example.coM   "
    }
  end
end
