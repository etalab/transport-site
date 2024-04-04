defmodule Transport.Jobs.PromoteReuserSpaceJob do
  @moduledoc """
  Send an email to a contact just after following a dataset for
  the first time.
  """
  use Oban.Worker, unique: [period: :infinity], max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"contact_id" => contact_id}}) do
    contact = DB.Repo.get!(DB.Contact, contact_id)

    {:ok, _} =
      contact.email
      |> Transport.PromoteReuserSpaceNotifier.promote_reuser_space()
      |> Transport.Mailer.deliver()

    :ok
  end
end

defmodule Transport.PromoteReuserSpaceNotifier do
  @moduledoc """
  Module in charge of building the email.
  """
  use Phoenix.Swoosh, view: TransportWeb.EmailView

  def promote_reuser_space(email) do
    new()
    |> from({"transport.data.gouv.fr", Application.fetch_env!(:transport, :contact_email)})
    |> to(email)
    |> reply_to(Application.fetch_env!(:transport, :contact_email))
    |> subject("Découvrez l'Espace réutilisateur")
    |> render_body("promote_reuser_space.html")
  end
end
