defmodule Mix.Tasks.Transport.OpenApiSpec do
  @moduledoc """
  Task to generate OpenAPI spec
  """
  alias TransportWeb.API.Spec

  def run([output_file]) do
    json = Poison.encode!(Spec.spec(), pretty: true)

    :ok = File.write!(output_file, json)
  end
end
