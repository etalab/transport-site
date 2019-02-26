defmodule TransportWeb.API.Schemas do
  @moduledoc """
    OpenAPI schema defintions
  """
  require OpenApiSpex
  alias OpenApiSpex.{Discriminator, ExternalDocumentation, Schema}

  defmodule GeometryBase do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema %{
      title: "GeometryBase",
      type: :object,
      description: "GeoJSon geometry",
      required: [:type],
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#geometry-objects"},
      properties: %{
        type: %Schema{
          type: :string,
          enum: ["Point", "LineString", "Polygon", "MultiPoint", "MultiLineString", "MultiPolygon"]
        }
      },
      discriminator: %Discriminator{
        propertyName: "type"
      }
    }
  end

  defmodule Point2D do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema %{
      title: "Point2D",
      type: :array,
      description: "Point in 2D space",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id2"},
      minItems: 2,
      maxItems: 2,
      items: %Schema{
        type: :number
      }
    }
  end

  defmodule LineString do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema %{
      title: "LineString",
      type: :object,
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id3"},
      allOf: [
          GeometryBase.schema,
          %Schema{
            type: :object,
            properties: %{
              coordinates: %Schema{type: :array, items: Point2D}
            }
          }
      ]
    }
  end

  defmodule Polygon do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema %{
      type: :object,
      title: "Polygon",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id4"},
      allOf: [
        GeometryBase.schema,
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: %Schema{type: :array, items: Point2D}}
          }
        }
      ]
    }
  end

  defmodule MultiPoint do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema %{
      type: :object,
      title: "MultiPoint",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id5"},
      allOf: [
        GeometryBase.schema,
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: Point2D}
          }
        }
      ]
    }
  end

  defmodule MultiLineString do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema %{
      type: :object,
      title: "MultiLineString",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id4"},
      allOf: [
        GeometryBase.schema,
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: %Schema{type: :array, items: Point2D}}
          }
        }
      ]
    }
  end

  defmodule MultiPolygon do
    @moduledoc false
    require OpenApiSpex
    OpenApiSpex.schema %{
      type: :object,
      title: "MultiPolygon",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id6"},
      allOf: [
        GeometryBase.schema,
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: %Schema{
              type: :array,
              items: %Schema{type: :array, items: Point2D}}
            }
          }
        }
      ]
    }
  end

  defmodule Geometry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema %{
      title: "Geometry",
      description: "Geometry object",
      type: :object,
      oneOf: [
        LineString.schema,
        Polygon.schema,
        MultiPoint.schema,
        MultiLineString.schema,
        MultiPolygon.schema
      ]
    }
  end

  defmodule Feature do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema %{
      type: :object,
      title: "Feature",
      description: "Feature object",
      required: [:type, :geometry, :properties],
      properties: %{
        type: %Schema{type: :string, enum: ["Feature"]},
        geometry: Geometry,
        properties: %Schema{type: :object},
        id: %Schema{
          oneOf: [%Schema{type: :string}, %Schema{type: :number}]
        }
      }
    }
  end

  defmodule FeatureCollection do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema %{
      type: :object,
      title: "FeatureCollection",
      description: "FeatureCollection object",
      properties: %{
        features: %Schema{type: :array, items: Feature},
      }
    }
  end

  defmodule AOMResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema %{
      title: "AOM",
      description: "AOM object",
      type: :object,
      properties: %{
        siren: %Schema{type: :string},
        nom: %Schema{type: :string},
        insee_commune_principale: %Schema{type: :string},
        forme_juridique: %Schema{type: :string},
        departement: %Schema{type: :string}
      }
    }
  end

  defmodule GeoJSONResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema %{
      title: "GeoJSONResponse",
      description: "Response in GeoJSON",
      type: :object,
      oneOf: [
        Geometry.schema,
        Feature.schema,
        FeatureCollection.schema
      ]
    }
  end

end
