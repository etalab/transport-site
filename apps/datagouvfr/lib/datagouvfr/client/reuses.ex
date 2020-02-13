defmodule Datagouvfr.Client.Reuses do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/reuses endpoints
  """
  alias Datagouvfr.Client.API, as: Client
  require Logger

  @endpoint "reuses"

  @spec get(map()) :: {:ok, any} | {:error, binary()}
  def get(%{datagouv_id: dataset_id}) do
    case Client.get(@endpoint, [], params: %{dataset: dataset_id}) do
      {:ok, %{"data" => data}} ->
        {:ok, Enum.map(data, &add_name/1)}

      {:error, %{body: body}} ->
        {:error, "Unable to get reuses of dataset #{dataset_id} because of #{body}"}

      {:error, %{reason: reason}} ->
        {:error, "Unable to get reuses of dataset #{dataset_id} because of #{reason}"}
    end
  end

  @spec add_name(map()) :: map()
  defp add_name(%{"owner" => nil} = reuse), do: reuse |> Map.put("owner", %{}) |> add_name
  defp add_name(reuse), do: put_in(reuse, ["owner", "name"], get_name(reuse))

  @spec get_name(map()) :: binary()
  defp get_name(%{"owner" => %{"name" => name}}), do: name
  defp get_name(%{"organization" => %{"name" => name}}), do: name
  defp get_name(%{"owner" => %{"first_name" => f_n, "last_name" => l_n}}), do: f_n <> " " <> l_n
  defp get_name(reuse), do: reuse
end
