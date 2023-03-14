defmodule TransportWeb.ConversionController do
  use TransportWeb, :controller

  def get(%Plug.Conn{} = conn, %{"resource_id" => resource_id, "convert_to" => convert_to}) do
    if convert_to in Ecto.Enum.dump_values(DB.DataConversion, :convert_to) do
      case DB.Resource.get_related_conversion_info(resource_id, convert_to) do
        nil ->
          conn |> conversion_not_found()

        %{url: url} ->
          trace_request(resource_id, convert_to)
          conn |> put_status(302) |> redirect(external: url)
      end
    else
      conn |> conversion_not_found("`convert_to` is not a possible value.")
    end
  end

  def get(%Plug.Conn{} = conn, _) do
    conn |> conversion_not_found("Unrecognized parameters.")
  end

  defp trace_request(resource_id, convert_to) do
    convert_to_atom = convert_to |> String.downcase() |> String.to_existing_atom()
    :telemetry.execute([:conversions, :get, convert_to_atom], %{}, %{target: "resource_id:#{resource_id}"})
  end

  defp conversion_not_found(%Plug.Conn{} = conn, explanation \\ "") do
    message =
      case explanation do
        "" -> "Conversion not found."
        explanation -> "Conversion not found. " <> explanation
      end

    conn |> put_status(:not_found) |> text(message)
  end
end
