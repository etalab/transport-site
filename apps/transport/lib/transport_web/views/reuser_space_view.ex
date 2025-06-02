defmodule TransportWeb.ReuserSpaceView do
  use TransportWeb, :view
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  def default_for_contact?(%DB.Token{default_for_contact_id: default_for_contact_id}, %DB.Contact{id: contact_id}) do
    default_for_contact_id == contact_id
  end
end
