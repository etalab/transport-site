defmodule DB.UserFeedbackTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save and read a feedback with encrypted email" do
    %DB.UserFeedback{}
    |> DB.UserFeedback.changeset(%{
      rating: :like,
      explanation: "<love>Awesome map!</love>",
      feature: :gtfs_stops,
      email: "Malotru@example.coM   "
    })
    |> DB.Repo.insert()

    expected_email = "malotru@example.com"

    assert %DB.UserFeedback{email: ^expected_email, explanation: "Awesome map!"} =
             DB.UserFeedback |> Ecto.Query.last() |> DB.Repo.one!()

    # Cannot get rows by using the email, because values are encrypted
    refute DB.UserFeedback |> where([f], f.email == ^expected_email) |> DB.Repo.exists?()
  end
end
