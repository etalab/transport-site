defmodule GBFS.ControllerHelpers do
  @moduledoc """
    Functions that are reused in GBFS controllers
  """
  use GBFS, :controller

  def assign_data_gbfs_json(conn, url_function) do
    conn
    |> assign(
      :data,
      %{
        "fr" => %{
          "feeds" =>
            Enum.map(
              [:system_information, :station_information, :station_status],
              fn a -> %{"name" => Atom.to_string(a), "url" => url_function.(conn, a)} end
            )
        }
      }
    )
  end
end
