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
        description: ~s"""
          Extra <a href="https://doc.transport.data.gouv.fr/outils/outils-disponibles-sur-le-pan/api">documentation</a>.

          The structure of the returned data is detailed at the bottom (see `Schemas`) and on each query (click on `Schema` near `Example Value`).

          To create a query, add the domain `https://transport.data.gouv.fr` and the path (e.g. `/api/datasets`).

          ## Authentication
          Tokens can be used when using the API. The token should be included in the `Authorization` HTTP header.
          If your token is `foo`, you should send HTTP requests with the header `Authorization: foo`.

          You can manage your token settings from your [reuser space](https://transport.data.gouv.fr/espace_reutilisateur).
        """,
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
