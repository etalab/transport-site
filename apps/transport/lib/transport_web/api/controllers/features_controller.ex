defmodule TransportWeb.API.FeaturesController do
  use TransportWeb, :controller

  def autocomplete(%Plug.Conn{} = conn, %{"contact_id" => contact_id, "name" => _, "type" => _} = payload) do
    contact_id =
      if is_integer(contact_id) do
        contact_id
      else
        nil
      end

    DB.FeatureUsage.insert!(
      :autocomplete,
      contact_id,
      payload |> Map.reject(fn {k, _} -> k == "contact_id" end)
    )

    conn |> json(%{status: :ok})
  end
end
