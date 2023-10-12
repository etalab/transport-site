defmodule Datagouvfr.Client.Organization do
  alias Datagouvfr.Client.API

  @endpoint "organizations"

  def get(id) do
    @endpoint
    |> Path.join(id)
    |> API.get()
  end
end
