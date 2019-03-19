defmodule Datagouvfr.Client.Reuses do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/reuses endpoints
  """
  import Datagouvfr.Client, only: [get_request: 4]
  require Logger

  @endpoint "reuses"

  def get(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    case get_request(conn, @endpoint, [], params: %{"dataset" => dataset_id}) do
      {:ok, %{"data" => data}} -> {:ok, Enum.map(data, &add_name/1)}
      {:error, error} ->
        Logger.error(error)
        {:error, error}
    end
  end

  defp add_name(reuse), do: put_in(reuse, ["owner", "name"], get_name(reuse))
  defp get_name(%{"owner" => %{"name" => name}}), do: name
  defp get_name(%{"owner" => %{"first_name" => f_n, "last_name" => l_n}}), do: f_n <> " " <> l_n
  defp get_name(reuse), do: reuse
end
