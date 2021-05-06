defmodule TransportWeb.Backoffice.DashboardView do
  use TransportWeb, :view

  @spec cell_class({boolean(), boolean()}) :: binary()
  def cell_class({_import_count = 0, _success_count}), do: "no_import"

  def cell_class({import_count, _success_count = 0}) when import_count > 0, do: "only_failures"

  def cell_class({import_count, success_count}) when import_count != success_count, do: "some_failures"

  def cell_class({import_count, success_count}) when import_count == success_count, do: "only_successes"
end
