defmodule Transport.Jobs.PromoteReuserSpaceJob do
  @moduledoc """
  Sends an email to a contact when they follow a dataset for
  the first time using the button.
  """
  use Oban.Worker, unique: [period: :infinity], max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_id" => contact_id}}) do
    contact = DB.Repo.get!(DB.Contact, contact_id)

    {:ok, _} =
      contact.email
      |> Transport.UserNotifier.promote_reuser_space()
      |> Transport.Mailer.deliver()

    :ok
  end
end
