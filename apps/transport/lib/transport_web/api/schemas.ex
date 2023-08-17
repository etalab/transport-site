defmodule TransportWeb.API.Schemas do
  @moduledoc """
    OpenAPI schema defintions
  """
  require OpenApiSpex
  alias OpenApiSpex.{ExternalDocumentation, Schema}

  defmodule GeometryBase do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GeometryBase",
      type: :object,
      description: "GeoJSon geometry",
      required: [:type],
      externalDocs: %ExternalDocumentation{
        url: "http://geojson.org/geojson-spec.html#geometry-objects"
      },
      properties: %{
        type: %Schema{
          type: :string,
          enum: [
            "Point",
            "LineString",
            "Polygon",
            "MultiPoint",
            "MultiLineString",
            "MultiPolygon"
          ]
        }
      }
    })
  end

  defmodule NumberItems do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "NumberItems",
      type: :number
    })
  end

  defmodule Point2D do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Point2D",
      type: :array,
      description: "Point in 2D space",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id2"},
      minItems: 2,
      maxItems: 2,
      items: NumberItems
    })
  end

  defmodule LineString do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LineString",
      type: :object,
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id3"},
      allOf: [
        GeometryBase.schema(),
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: Point2D}
          }
        }
      ]
    })
  end

  defmodule Polygon do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      title: "Polygon",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id4"},
      allOf: [
        GeometryBase.schema(),
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: %Schema{type: :array, items: Point2D}}
          }
        }
      ]
    })
  end

  defmodule MultiPoint do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      title: "MultiPoint",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id5"},
      allOf: [
        GeometryBase.schema(),
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: Point2D}
          }
        }
      ]
    })
  end

  defmodule MultiLineString do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      title: "MultiLineString",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id4"},
      allOf: [
        GeometryBase.schema(),
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{type: :array, items: %Schema{type: :array, items: Point2D}}
          }
        }
      ]
    })
  end

  defmodule MultiPolygon do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      title: "MultiPolygon",
      description: "GeoJSon geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id6"},
      allOf: [
        GeometryBase.schema(),
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{
              type: :array,
              items: %Schema{type: :array, items: %Schema{type: :array, items: Point2D}}
            }
          }
        }
      ]
    })
  end

  defmodule Geometry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Geometry",
      description: "Geometry object",
      type: :object,
      oneOf: [
        LineString.schema(),
        Polygon.schema(),
        MultiPoint.schema(),
        MultiLineString.schema(),
        MultiPolygon.schema()
      ]
    })
  end

  defmodule Feature do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
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
    })
  end

  defmodule FeatureCollection do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      title: "FeatureCollection",
      description: "FeatureCollection object",
      properties: %{
        features: %Schema{type: :array, items: Feature}
      }
    })
  end

  defmodule AOMResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AOMResponse",
      description:
        "AOM object, as returned from AOMs endpoints (DEPRECATED, only there for retrocompatibility, use covered_area instead)",
      type: :object,
      # this means key must be present (but does not specify if value is nullable or not)
      required: [
        :siren,
        :nom,
        :insee_commune_principale,
        :forme_juridique,
        :departement
      ],
      properties: %{
        siren: %Schema{type: :string, nullable: true},
        nom: %Schema{type: :string, nullable: false},
        insee_commune_principale: %Schema{type: :string, nullable: false},
        forme_juridique: %Schema{type: :string, nullable: false},
        departement: %Schema{type: :string, nullable: false}
      },
      # this forbids unknown property - keep to false to ensure `assert_schema`
      # detects out of sync specifications during the tests.
      additionalProperties: false
    })
  end

  defmodule AOMShortRef do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AOMShortRef",
      description:
        "AOM object, as embedded in datasets (short version - DEPRECATED, only there for retrocompatibility, use covered_area instead)",
      type: :object,
      required: [:name],
      properties: %{
        # nullable because we saw it null in actual production data
        siren: %Schema{type: :string, nullable: true},
        name: %Schema{type: :string, nullable: true}
      },
      additionalProperties: false
    })
  end

  defmodule GeoJSONResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GeoJSONResponse",
      description: "Response in GeoJSON",
      type: :object,
      oneOf: [
        Geometry.schema(),
        Feature.schema(),
        FeatureCollection.schema()
      ]
    })
  end

  defmodule Utils do
    @moduledoc false
    def get_resource_prop(conversions: false),
      do: %{
        datagouv_id: %Schema{
          type: :string,
          description: "Data gouv id of the resource",
          nullable: false
        },
        id: %Schema{
          type: :integer,
          description: "transport.data.gouv.fr specific id",
          nullable: false
        },
        format: %Schema{
          type: :string,
          description: "The format of the resource (GTFS, NeTEx, etc.)",
          nullable: false
        },
        is_available: %Schema{
          type: :boolean,
          description: "Availability of the resource",
          nullable: false
        },
        original_url: %Schema{
          type: :string,
          description: "Direct URL of the file",
          nullable: false
        },
        url: %Schema{type: :string, description: "Stable URL of the file", nullable: false},
        page_url: %Schema{
          type: :string,
          description: "URL of the resource on transport.data.gouv.fr",
          nullable: false
        },
        features: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Features",
          nullable: false
        },
        title: %Schema{type: :string, description: "Title of the resource", nullable: false},
        filesize: %Schema{
          type: :integer,
          description: "Size of the resource in bytes",
          nullable: false
        },
        metadata: %Schema{
          type: :object,
          description: "Some metadata about the resource",
          nullable: false
        },
        type: %Schema{type: :string, description: "Category of the data", nullable: false},
        modes: %Schema{
          type: :array,
          items: %Schema{type: :string, nullable: false},
          description: "Types of transportation",
          nullable: false
        },
        updated: %Schema{
          type: :string,
          format: "date-time",
          description: "Last update date-time",
          nullable: false
        },
        schema_name: %Schema{
          type: :string,
          description: "Data schema followed by the resource",
          nullable: false
        },
        schema_version: %Schema{
          type: :string,
          description: "Version of the data schema followed by the resource",
          nullable: false
        }
      }

    # TODO: review - I believe conversions are not available at the moment in the output
    def get_resource_prop(conversions: true),
      do:
        [conversions: false]
        |> get_resource_prop()
        |> Map.put(:conversions, %Schema{
          type: :object,
          description: "Available conversions of the resource in other formats",
          properties: %{
            GeoJSON: %Schema{
              type: :object,
              description: "Conversion to the GeoJSON format",
              properties: conversion_properties()
            },
            NeTEx: %Schema{
              type: :object,
              description: "Conversion to the NeTEx format",
              properties: conversion_properties()
            }
          }
        })

    defp conversion_properties,
      do: %{
        filesize: %Schema{type: :integer, description: "File size in bytes"},
        last_check_conversion_is_up_to_date: %Schema{
          type: :string,
          format: "date-time",
          description: "Last datetime (UTC) it was checked the converted file is still up-to-date with the resource"
        },
        stable_url: %Schema{type: :string, description: "The converted file stable download URL"}
      }
  end

  defmodule Resource do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%Schema{
      type: :object,
      description: "A single resource",
      # TODO: fill this. Required fields are keys which must always been present (even if data is null/empty)
      required: [],
      properties: Utils.get_resource_prop(conversions: true),
      additionalProperties: false
    })
  end

  # TODO: remove in favor of only Resource + a `is_community_resource` boolean flag?
  # https://github.com/etalab/transport-site/issues/3407
  defmodule CommunityResource do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%Schema{
      type: :object,
      description: "A single community resource",
      # TODO: fill
      required: [],
      properties:
        [conversions: false]
        |> Utils.get_resource_prop()
        |> Map.put(:community_resource_publisher, %Schema{
          type: :string,
          description: "Name of the producer of the community resource"
        })
        |> Map.put(
          :original_resource_url,
          %Schema{
            type: :string,
            description: """
            some community resources have been generated from another dataset (like the generated NeTEx / GeoJson).
            Those resources have a `original_resource_url` equals to the original resource's `original_url`
            """
          }
        ),
      additionalProperties: false
    })
  end

  defmodule Publisher do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Publisher",
      description: "Publisher",
      type: :object,
      # non nullable I think - but tests will need to be adapted
      properties: %{
        name: %Schema{type: :string, nullable: true},
        type: %Schema{type: :string, nullable: true}
      },
      additionalProperties: false
    })
  end

  defmodule Dataset do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Dataset",
      description: "A dataset is a composed of one or more resources",
      type: :object,
      properties: %{
        datagouv_id: %Schema{type: :string, description: "Data gouv id for this dataset", nullable: false},
        id: %Schema{type: :string, description: "Same as datagouv_id", nullable: false},
        updated: %Schema{
          type: :string,
          format: :"date-time",
          description: "The last update of any resource of that dataset"
        },
        # TODO: see why this is not found in production currently!!!
        # TODO: be more specific about the format
        history: %Schema{type: :array},
        page_url: %Schema{type: :string, description: "transport.data.gouv.fr page for this dataset", nullable: false},
        publisher: Publisher.schema(),
        slug: %Schema{type: :string, description: "unique dataset slug", nullable: false},
        title: %Schema{type: :string, nullable: false},
        # TODO: move to nullable, but tests need fixin'
        type: %Schema{type: :string, nullable: true},
        licence: %Schema{type: :string, description: "The licence of the dataset"},
        created_at: %Schema{type: :string, format: :date, description: "Date of creation of the dataset"},
        aom: AOMShortRef.schema(),
        resources: %Schema{
          type: :array,
          description: "All the resources (files) associated with the dataset",
          items: Resource
        },
        community_resources: %Schema{
          type: :array,
          description: "All the community resources (files published by the community) associated with the dataset",
          items: CommunityResource
        },
        covered_area: %Schema{
          type: :object,
          properties: %{
            aom: AOMShortRef,
            name: %Schema{type: :string, description: "TODO"},
            type: %Schema{type: :string, description: "TODO"}
          },
          additionalProperties: false
        }
      },
      additionalProperties: false
    })
  end

  defmodule DatasetsResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DatasetsResponse",
      type: :array,
      items: Dataset.schema()
    })
  end

  defmodule AutocompleteItem do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Autocomplete result",
      description: "One result of the autocomplete",
      type: :object,
      required: [:url, :type, :name],
      properties: %{
        url: %Schema{type: :string, description: "URL of the Resource"},
        type: %Schema{type: :string, description: "type of the resource (commune, region, aom)"},
        name: %Schema{type: :string, description: "name of the resource"}
      },
      additionalProperties: false
    })
  end

  defmodule AutocompleteResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AutocompleteResponse",
      description: "An array of matching results",
      type: :array,
      items: AutocompleteItem
    })
  end
end
