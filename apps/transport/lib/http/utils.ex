defmodule Transport.Http.Utils do
  @moduledoc """
  Useful functions to work with http requests
  """

  def location_header(headers) do
    for {key, value} <- headers, String.downcase(key) == "location" do
      value
    end
  end
end
