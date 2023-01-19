defmodule DB.Notification do
  @moduledoc """
  A list of emails notifications sent, with email addresses encrypted
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "notifications" do
    field(:reason, Ecto.Enum,
      values: [:dataset_with_error, :resource_unavailable, :expiration, :new_dataset, :dataset_now_licence_ouverte]
    )

    belongs_to(:dataset, DB.Dataset)
    field(:email, DB.Encrypted.Binary)
    # Should be used to search rows matching an email address
    # https://hexdocs.pm/cloak_ecto/install.html#usage
    field(:email_hash, Cloak.Ecto.SHA256)

    timestamps(type: :utc_datetime_usec)
  end

  def insert!(reason, %DB.Dataset{id: dataset_id}, email) do
    __MODULE__
    |> changeset(%{email: email, dataset_id: dataset_id, reason: @notification_reason})
    |> DB.Repo.insert!()
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:reason, :dataset_id, :email])
    |> validate_required([:reason, :dataset_id, :email])
    |> validate_format(:email, ~r/@/)
    |> put_hashed_fields()
  end

  defp put_hashed_fields(%Ecto.Changeset{} = changeset) do
    changeset
    |> put_change(:email_hash, get_field(changeset, :email))
  end
end
