defmodule Datagouvfr.Client.Reuses do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/reuses endpoints
  """
  alias Datagouvfr.Client.OAuth, as: Client
  alias Transport.Dataset
  require Logger

  @endpoint "reuses"

  @spec get(Plug.Conn.t(), Dataset.t()) :: nil | {:ok, [any]}
  def get(%Plug.Conn{} = conn, %Dataset{datagouv_id: dataset_id}) do
    case Client.get(conn, @endpoint, [], params: %{"dataset" => dataset_id}) do
      {:ok, %{"data" => data}} -> {:ok, Enum.map(data, &add_name/1)}
      {:error, %OAuth2.Response{body: body}} ->
        Logger.error("Unable to get reuses of dataset #{dataset_id} because of #{body}")
        nil
      {:error, %OAuth2.Error{reason: reason}} ->
        Logger.error("Unable to get reuses of dataset #{dataset_id} because of #{reason}")
        nil
    end
  end

  defp add_name(%{"owner" => nil} = reuse), do: reuse |> Map.put("owner", %{}) |> add_name
  defp add_name(reuse), do: put_in(reuse, ["owner", "name"], get_name(reuse))

  defp get_name(%{"owner" => %{"name" => name}}), do: name
  defp get_name(%{"organization" => %{"name" => name}}), do: name
  defp get_name(%{"owner" => %{"first_name" => f_n, "last_name" => l_n}}), do: f_n <> " " <> l_n
  defp get_name(reuse), do: reuse
end
