defmodule TransportWeb.API.Spec do
  @moduledoc """
  OpenAPI specifications
  """
  alias OpenApiSpex.{Contact, Info, OpenApi, Paths}

  @spec spec :: OpenApiSpex.OpenApi.t()
  def spec do
    %OpenApi{
      # # https://github.com/OAI/OpenAPI-Specification/blob/main/versions/2.0.md#info-object
      info: %Info{
        title: "transport.data.gouv.fr API",
        version: "1.0",
        description: ~S(Extra <a href="https://doc.transport.data.gouv.fr/administration-des-donnees/outils/api">documentation</a>),
        contact: %Contact{
          name: "API email support",
          email: Application.fetch_env!(:transport, :contact_email)
        }
      },
      paths: Paths.from_router(TransportWeb.API.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
