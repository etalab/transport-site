defmodule TransportWeb.API.Schemas do
  @moduledoc """
    OpenAPI schema defintions

    Useful documentation:
    - https://json-schema.org/understanding-json-schema/reference/array.html
    - https://json-schema.org/understanding-json-schema/reference/object.html
    - https://json-schema.org/understanding-json-schema/reference/string.html

    A good chunk of our GeoJSON responses do not pass our OpenAPI specs. It would need more work.

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
      },
      # allow extra properties since this is used as a composable base
      additionalProperties: true
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
      ],
      additionalProperties: false
    })
  end

  defmodule Polygon do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      title: "Polygon",
      description: "GeoJSON geometry",
      externalDocs: %ExternalDocumentation{url: "http://geojson.org/geojson-spec.html#id4"},
      allOf: [
        GeometryBase.schema(),
        %Schema{
          type: :object,
          properties: %{
            coordinates: %Schema{
              type: :array,
              items: %Schema{
                type: :array,
                items: %Schema{
                  type: :array,
                  items: Point2D
                }
              }
            }
          }
        }
      ],
      additionalProperties: false
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
      ],
      additionalProperties: false
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
      ],
      additionalProperties: false
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
      ],
      additionalProperties: false
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
      ],
      additionalProperties: false
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
        properties: %Schema{
          type: :object,
          properties: %{
            id: %Schema{
              oneOf: [%Schema{type: :string}, %Schema{type: :number}]
            }
          }
        }
      },
      additionalProperties: false
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
        features: %Schema{type: :array, items: Feature},
        type: %Schema{type: :string, enum: ["FeatureCollection"], required: true},
        name: %Schema{type: :string}
      },
      additionalProperties: false
    })
  end

  defmodule AOMResponse do
    @moduledoc false
    require OpenApiSpex

    @properties %{
      siren: %Schema{type: :string, nullable: true},
      nom: %Schema{type: :string},
      insee_commune_principale: %Schema{type: :string},
      forme_juridique: %Schema{type: :string},
      departement: %Schema{type: :string}
    }

    OpenApiSpex.schema(%{
      title: "AOMResponse",
      description: "AOM object, as returned from AOMs endpoints",
      type: :object,
      properties: @properties,
      required: @properties |> Map.keys(),
      additionalProperties: false
    })
  end

  defmodule AOM do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AOM",
      description: "AOM object, as used in covered area and legal owners",
      type: :object,
      required: [:name, :siren],
      properties: %{
        name: %Schema{type: :string},
        siren: %Schema{type: :string}
      },
      additionalProperties: false
    })
  end

  defmodule Region do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Region",
      description: "Region object",
      type: :object,
      required: [:name, :insee],
      properties: %{
        name: %Schema{type: :string},
        insee: %Schema{type: :string}
      },
      additionalProperties: false
    })
  end

  defmodule City do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "City",
      description: "City object",
      type: :object,
      required: [:name, :insee],
      properties: %{
        name: %Schema{type: :string},
        insee: %Schema{type: :string}
      },
      additionalProperties: false
    })
  end

  defmodule AdministrativeDivision do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AdministrativeDivision",
      type: :object,
      required: [
        :type,
        :insee,
        :nom
      ],
      properties: %{
        type: %Schema{
          type: :string,
          enum: Ecto.Enum.dump_values(DB.AdministrativeDivision, :type),
          required: true
        },
        insee: %Schema{type: :string, required: true},
        nom: %Schema{type: :string, required: true}
      },
      additionalProperties: false
    })
  end

  defmodule CoveredArea do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CoveredArea",
      type: :array,
      items: AdministrativeDivision.schema(),
      additionalProperties: false
    })
  end

  defmodule LegalOwners do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LegalOwners",
      type: :object,
      properties: %{
        aoms: %Schema{
          type: :array,
          items: AOM.schema()
        },
        regions: %Schema{
          type: :array,
          items: Region.schema()
        },
        company: %Schema{type: :string, nullable: true}
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
      ],
      additionalProperties: false
    })
  end

  defmodule ErrorJSONResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorJSONResponse",
      description: "Error Response in JSON",
      type: :object,
      properties: %{
        error: %Schema{type: :string}
      },
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
      properties: %{
        name: %Schema{type: :string},
        id: %Schema{type: :string},
        type: %Schema{type: :string}
      },
      additionalProperties: false
    })
  end

  defmodule ResourceUtils do
    @moduledoc false
    def get_resource_prop(conversions: false),
      do: %{
        datagouv_id: %Schema{
          type: :string,
          description: "Data gouv id of the resource"
        },
        id: %Schema{
          type: :integer,
          description: "transport.data.gouv.fr's ID"
        },
        format: %Schema{
          type: :string,
          description: "The format of the resource (GTFS, NeTEx, etc.)"
        },
        is_available: %Schema{
          type: :boolean,
          description: "Availability of the resource"
        },
        original_url: %Schema{
          type: :string,
          description: "Direct URL of the file"
        },
        url: %Schema{type: :string, description: "Stable URL of the file"},
        page_url: %Schema{
          type: :string,
          description: "URL of the resource on transport.data.gouv.fr"
        },
        features: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Features"
        },
        title: %Schema{type: :string, description: "Title of the resource"},
        filesize: %Schema{
          type: :integer,
          description: "Size of the resource in bytes"
        },
        metadata: %Schema{
          type: :object,
          description: "Some metadata about the resource"
        },
        type: %Schema{type: :string, description: "Category of the data"},
        modes: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Types of transportation"
        },
        updated: %Schema{
          type: :string,
          format: "date-time",
          description: "Last update date-time"
        },
        schema_name: %Schema{
          type: :string,
          description: "Data schema followed by the resource"
        },
        schema_version: %Schema{
          type: :string,
          description: "Version of the data schema followed by the resource"
        }
      }

    # conversions are only shown in the detailed dataset view
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
              required: conversion_properties() |> Map.keys(),
              properties: conversion_properties(),
              additionalProperties: false
            },
            NeTEx: %Schema{
              type: :object,
              description: "Conversion to the NeTEx format",
              required: conversion_properties() |> Map.keys(),
              properties: conversion_properties(),
              additionalProperties: false
            }
          }
        })

    def get_community_resource_prop do
      [conversions: false]
      |> ResourceUtils.get_resource_prop()
      |> Map.put(:community_resource_publisher, %Schema{
        type: :string,
        description: "Name of the producer of the community resource"
      })
      |> Map.put(
        :original_resource_url,
        %Schema{
          type: :string,
          description: """
          Some community resources have been generated from another dataset (like the generated NeTEx / GeoJSON).
          Those resources have a `original_resource_url` equals to the original resource's `original_url`
          """
        }
      )
    end

    # DRYing keys here
    def get_resource_optional_properties_keys do
      [
        :features,
        :filesize,
        :metadata,
        :modes,
        :original_resource_url,
        :schema_name,
        :schema_version
      ]
    end

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

  defmodule DetailedResource do
    @moduledoc false
    require OpenApiSpex

    @properties ResourceUtils.get_resource_prop(conversions: true)
    @optional_properties ResourceUtils.get_resource_optional_properties_keys()

    OpenApiSpex.schema(%Schema{
      type: :object,
      description: "A single resource (including conversions)",
      required: (@properties |> Map.keys()) -- @optional_properties,
      properties: @properties,
      additionalProperties: false
    })
  end

  defmodule SummarizedResource do
    @moduledoc false
    require OpenApiSpex

    @properties ResourceUtils.get_resource_prop(conversions: false)
    @optional_properties ResourceUtils.get_resource_optional_properties_keys()

    OpenApiSpex.schema(%Schema{
      type: :object,
      description: "A single resource (summarized version)",
      required: (@properties |> Map.keys()) -- @optional_properties,
      properties: @properties,
      additionalProperties: false
    })
  end

  defmodule CommunityResource do
    @moduledoc false
    require OpenApiSpex

    @properties ResourceUtils.get_community_resource_prop()
    @optional_properties ResourceUtils.get_resource_optional_properties_keys()

    OpenApiSpex.schema(%Schema{
      type: :object,
      description: "A single community resource",
      required: (@properties |> Map.keys()) -- @optional_properties,
      properties: @properties,
      additionalProperties: false
    })
  end

  defmodule ResourceHistory do
    @moduledoc false
    require OpenApiSpex

    @properties %{
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"},
      last_up_to_date_at: %Schema{type: :string, format: "date-time", nullable: true},
      payload: %Schema{type: :object, description: "Payload (loosely specified at the moment)"},
      latest_schema_version_to_date: %Schema{type: :string},
      permanent_url: %Schema{type: :string},
      resource_latest_url: %Schema{type: :string},
      resource_url: %Schema{type: :string},
      # NOTE: apparently, can be nil sometimes! This should be investigated
      resource_id: %Schema{type: :integer, nullable: true},
      schema_name: %Schema{type: :string},
      schema_version: %Schema{type: :string},
      title: %Schema{type: :string},
      uuid: %Schema{type: :string}
    }
    @optional_properties [
      :latest_schema_version_to_date,
      :permanent_url,
      :resource_latest_url,
      :resource_url,
      :schema_name,
      :schema_version,
      :uuid,
      :title
    ]

    OpenApiSpex.schema(%Schema{
      type: :object,
      description: "A resource version",
      required: (@properties |> Map.keys()) -- @optional_properties,
      properties: @properties,
      additionalProperties: false
    })
  end

  defmodule DatasetUtils do
    @moduledoc false

    def get_dataset_prop(details: details) do
      # base resource comes in 2 flavors
      resource_type = if details == true, do: DetailedResource, else: SummarizedResource

      base = %{
        datagouv_id: %Schema{
          type: :string,
          description: "Data gouv id for this dataset"
        },
        id: %Schema{type: :string, description: "Same as datagouv_id"},
        updated: %Schema{
          type: :string,
          format: :"date-time",
          description: "The last update of any resource of that dataset (`null` if the dataset has no resources)",
          nullable: true
        },
        page_url: %Schema{
          type: :string,
          description: "transport.data.gouv.fr page for this dataset"
        },
        publisher: Publisher.schema(),
        slug: %Schema{type: :string, description: "unique dataset slug"},
        title: %Schema{type: :string},
        type: %Schema{type: :string},
        licence: %Schema{
          type: :string,
          description: "The licence of the dataset"
        },
        created_at: %Schema{
          type: :string,
          format: :date,
          description: "Date of creation of the dataset"
        },
        resources: %Schema{
          type: :array,
          description: "All the resources associated with the dataset",
          # NOTE: community resources will have to be removed from here
          # https://github.com/etalab/transport-site/issues/3407
          items: %Schema{anyOf: [resource_type, CommunityResource]}
        },
        community_resources: %Schema{
          type: :array,
          description: "All the community resources (published by the community) associated with the dataset",
          items: CommunityResource
        },
        covered_area: CoveredArea.schema(),
        legal_owners: LegalOwners.schema()
      }

      if details do
        base
        |> Map.put(:history, %Schema{type: :array, items: ResourceHistory})
      else
        base
      end
    end
  end

  defmodule DatasetSummary do
    @moduledoc false
    require OpenApiSpex

    @properties DatasetUtils.get_dataset_prop(details: false)

    OpenApiSpex.schema(%{
      title: "DatasetSummary",
      description: "A dataset is a composed of one or more resources (summarized version)",
      type: :object,
      required: @properties |> Map.keys(),
      properties: @properties,
      additionalProperties: false
    })
  end

  defmodule DatasetDetails do
    @moduledoc false
    require OpenApiSpex

    @properties DatasetUtils.get_dataset_prop(details: true)

    OpenApiSpex.schema(%{
      title: "DatasetDetails",
      description:
        "A dataset is a composed of one or more resources (detailed version, including history & conversions).",
      type: :object,
      required: @properties |> Map.keys(),
      properties: @properties,
      additionalProperties: false
    })
  end

  defmodule DatasetsResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DatasetsResponse",
      type: :array,
      items: DatasetSummary.schema()
    })
  end

  defmodule AutocompleteItem do
    @moduledoc false
    require OpenApiSpex

    @properties %{
      url: %Schema{type: :string, description: "URL of the Resource"},
      type: %Schema{type: :string, description: "type of the resource (commune, region, aom)"},
      name: %Schema{type: :string, description: "name of the resource"}
    }

    OpenApiSpex.schema(%{
      title: "Autocomplete result",
      description: "One result of the autocomplete",
      type: :object,
      required: @properties |> Map.keys(),
      properties: @properties,
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
