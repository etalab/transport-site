defmodule Datagouvfr.Client.Reuses.Wrapper do
  @moduledoc """
  Behavior for Datagouvfr Reuses
  """
  @callback get(map()) :: {:ok, list()} | {:error, binary()}

  def impl, do: Application.fetch_env!(:datagouvfr, :datagouvfr_reuses)

  def get(dataset), do: impl().get(dataset)
end

defmodule Datagouvfr.Client.Reuses.Dummy do
  @moduledoc """
  Dummy reuses, outputing empty list
  """
  @behaviour Datagouvfr.Client.Reuses.Wrapper

  @impl true
  def get(_), do: {:ok, []}
end

defmodule Datagouvfr.Client.Reuses do
  @moduledoc """
  A client to manipulate https://www.data.gouv.fr/api/1/reuses endpoints
  """
  alias Datagouvfr.Client.API, as: Client
  require Logger
  @behaviour Datagouvfr.Client.Reuses.Wrapper

  @endpoint "reuses"

  @impl true
  def get(%{datagouv_id: dataset_id}) do
    case Client.get(@endpoint, [], params: %{dataset: dataset_id}) do
      {:ok, %{"data" => data}} ->
        {:ok, Enum.map(data, &add_name/1)}

      {:error, body} when is_map(body) ->
        {:error, "Unable to get reuses of dataset #{dataset_id} because of #{inspect(body)}"}

      {:error, %Jason.DecodeError{}} ->
        {:error, "Unable to get reuses of dataset #{dataset_id} could not decode JSON"}
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
