defmodule TransportWeb.API.Spec do
  @moduledoc """
  OpenAPI specifications
  """
  alias OpenApiSpex.{Info, OpenApi, Paths}

  def spec do
    %OpenApi{
      info: %Info{
        title: "Transport.data.gouv.fr API",
        version: "1.0"
      },
      paths: Paths.from_router(TransportWeb.API.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
