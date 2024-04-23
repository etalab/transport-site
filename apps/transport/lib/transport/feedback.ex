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
    |> sanitize_inputs([:explanation, :email])
    |> validate_format(:email, ~r/@/)
    |> lowercase_email()
  end

  defp sanitize_inputs(changeset, keys) do
    Enum.reduce(keys, changeset, fn key, acc -> sanitize_field(acc, key) end)
  end

  defp sanitize_field(changeset, key) do
    case get_change(changeset, key) do
      nil -> changeset
      value -> put_change(changeset, key, value |> String.trim() |> HtmlSanitizeEx.strip_tags())
    end
  end

  defp lowercase_email(%Ecto.Changeset{} = changeset) do
    update_change(changeset, :email, &String.downcase/1)
  end
end
