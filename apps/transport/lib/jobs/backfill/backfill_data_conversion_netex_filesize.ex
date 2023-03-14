defmodule Transport.Jobs.Backfill.DataConversionNeTExFilesize do
  @moduledoc """
  Backfill of `DB.DataConversion.payload` to fix the filesize for NeTEx conversions

  See https://github.com/etalab/transport-site/issues/2134
  """
  use Oban.Worker
  import Ecto.Query
  alias DB.{DataConversion, Repo}

  @backfill_delay 1

  @impl true
  def perform(%{args: %{"data_conversion_id" => data_conversion_id, "backfill" => true}}) do
    with :ok <- perform(%{args: %{"data_conversion_id" => data_conversion_id}}) do
      case fetch_next(data_conversion_id) do
        next_id when is_integer(next_id) ->
          %{data_conversion_id: next_id, backfill: true} |> new(schedule_in: @backfill_delay) |> Oban.insert()

        nil ->
          :ok
      end
    end
  end

  def perform(%{args: %{"data_conversion_id" => data_conversion_id}}) do
    update_data_conversion(data_conversion_id)
    :ok
  end

  defp fetch_next(data_conversion_id) do
    DataConversion
    |> where([dc], dc.id > ^data_conversion_id and dc.convert_to == :NeTEx)
    |> order_by(asc: :id)
    |> limit(1)
    |> select([dc], dc.id)
    |> Repo.one()
  end

  defp update_data_conversion(data_conversion_id) do
    DataConversion |> Repo.get!(data_conversion_id) |> do_update()
  end

  defp do_update(
         %DataConversion{convert_from: :GTFS, convert_to: :NeTEx, payload: %{"permanent_url" => url} = payload} = dc
       ) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    {:ok, %{headers: headers}} = http_client.head(url)
    {_, filesize} = headers |> Enum.find(fn {h, _} -> h == "content-length" end)

    dc |> Ecto.Changeset.change(%{payload: %{payload | "filesize" => String.to_integer(filesize)}}) |> Repo.update!()
  end
end
