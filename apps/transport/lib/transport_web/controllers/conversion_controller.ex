defmodule TransportWeb.ConversionController do
  use TransportWeb, :controller

  def get(%Plug.Conn{} = conn, %{"resource_id" => resource_id, "convert_to" => convert_to}) do
    acceptable_formats = DB.DataConversion.available_conversion_formats() |> Enum.map(&to_string/1)

    if convert_to in acceptable_formats do
      case DB.Resource.get_related_conversion_info(resource_id, String.to_existing_atom(convert_to)) do
        nil ->
          conn |> conversion_not_found()

        %{url: url, resource_history_last_up_to_date_at: %DateTime{} = last_up_to_date_at} ->
          trace_request(resource_id, convert_to)

          conn
          |> put_resp_header("etag", md5_hash(url))
          |> put_resp_header("cache-control", "public, max-age=300")
          |> put_resp_header("x-robots-tag", "noindex")
          |> put_resp_header("x-last-up-to-date-at", last_up_to_date_at |> DateTime.to_iso8601())
          |> put_status(302)
          |> redirect(external: url)
      end
    else
      conn |> conversion_not_found("`#{convert_to}` is not a possible value.")
    end
  end

  def get(%Plug.Conn{} = conn, _) do
    conn |> conversion_not_found("Unrecognized parameters.")
  end

  @doc """
  iex> md5_hash("elixir")
  "74b565865a192cc8693c530d48eb383a"
  """
  def md5_hash(value) do
    :md5 |> :crypto.hash(value) |> Base.encode16(case: :lower)
  end

  defp trace_request(resource_id, convert_to) when is_binary(convert_to) do
    convert_to_atom = convert_to |> String.to_existing_atom()
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
