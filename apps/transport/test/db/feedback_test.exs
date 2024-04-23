defmodule DB.FeedbackTest do
  use ExUnit.Case, async: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save and read a feedback with encrypted email" do
    %DB.Feedback{}
    |> DB.Feedback.changeset(%{
      rating: :like,
      explanation: "<love>Awesome map!</love>",
      feature: :"gtfs-stops",
      email: "Malotru@example.coM   "
    })
    |> DB.Repo.insert()

    feedback = DB.Feedback |> Ecto.Query.last() |> DB.Repo.one()

    assert feedback.email == "malotru@example.com"
    assert feedback.explanation == "Awesome map!"
  end
end
