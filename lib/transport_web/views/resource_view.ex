defmodule TransportWeb.ResourceView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers

  def format_related_objects(nil), do: ""
  def format_related_objects(related_objects) do
    related_objects
    |> Enum.map(fn %{"id" => id, "name" => name} -> "#{name} (#{id})" end)
    |> Enum.join(", ")
  end
end
