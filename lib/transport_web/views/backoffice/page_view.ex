defmodule TransportWeb.Backoffice.PageView do
  use TransportWeb, :view
  import TransportWeb.PaginationHelpers
  import TransportWeb.DatasetView, only: [first_gtfs: 1]
  alias Transport.Dataset
end
