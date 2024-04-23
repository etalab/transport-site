defmodule DB.Feedback do
  @moduledoc """
  Stores feedback from users about the application sent trhough the feedback form
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  schema "feedback" do
    field(:email, DB.Encrypted.Binary)
    field(:explanation, :string)
    field(:feature, Ecto.Enum, values: [:"gtfs-stops", :"on-demand-validation", :"gbfs-validation", :"reuser-space"])
    field(:rating, Ecto.Enum, values: [:like, :neutral, :dislike])

    timestamps()
  end

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [:rating, :explanation, :email, :feature])
    |> validate_required([:rating, :feature, :explanation])
    |> validate_format(:email, ~r/@/)
    |> lowercase_email()
  end

  defp lowercase_email(%Ecto.Changeset{} = changeset) do
    update_change(changeset, :email, &String.downcase/1)
  end
end
