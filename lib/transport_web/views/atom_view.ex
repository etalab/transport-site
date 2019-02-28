defmodule TransportWeb.AtomView do
  use TransportWeb, :view
  alias Timex.Timezone

  def format_date(nil), do: ""
  def format_date(date) do
    date
    |> Timex.parse!("{ISO:Extended}")
    |> Timezone.convert("Europe/Paris")
    |> Timex.format!("{RFC3339}")
  end

  def updated(resources) do
    resources
    |> Enum.map(fn r -> r.last_update end)
    |> Enum.reject(fn r -> is_nil(r) end)
    |> Enum.max
    |> format_date
  end
end
