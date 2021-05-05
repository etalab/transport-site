defmodule TransportWeb.Backoffice.DashboardView do
  use TransportWeb, :view

  @spec cell_class({boolean(), boolean()}) :: binary()
  def cell_class({true, _import_failure}), do: "crash"

  def cell_class({false, import_failure}) do
    case import_failure do
      true -> "failure"
      false -> "success"
    end
  end
end
