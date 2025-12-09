defmodule TransportWeb.SeoMetadata do
  @moduledoc """
  Module to set a title and a description for each pages.
  The default title/description are defined in app.html.eex
  """
  use Gettext, backend: TransportWeb.Gettext

  @spec metadata(any(), any()) :: %{optional(:title) => binary(), optional(:description) => binary()}
  def metadata(TransportWeb.DatasetView, %{q: q}) when not is_nil(q),
    do: %{
      title: dgettext("seo", "%{q}: Available transport open datasets", q: q)
    }

  def metadata(TransportWeb.DatasetView, %{dataset: dataset}) do
    formats =
      case DB.Dataset.formats(dataset) do
        [] -> ""
        l -> "(#{Enum.join(l, ", ")})"
      end

    %{
      title:
        dgettext("seo", "%{custom_title} - Open %{formats} datasets - %{territory}",
          custom_title: dataset.custom_title,
          territory: DB.Dataset.get_covered_area_or_nil(dataset),
          formats: formats
        )
    }
  end

  def metadata(TransportWeb.DatasetView, %{
        page_title: %{name: name},
        conn: %{params: %{"departement" => _}}
      }),
      do: %{
        title: dgettext("seo", "%{name} department: Transport open datasets", name: name)
      }

  def metadata(TransportWeb.DatasetView, %{page_title: %{type: "EPCI", name: name}}),
    do: %{
      title: dgettext("seo", "%{name} EPCI: Transport open datasets", name: name)
    }

  def metadata(TransportWeb.DatasetView, %{
        page_title: %{name: name},
        conn: %{params: %{"commune" => _}}
      }),
      do: %{
        title: dgettext("seo", "Transport open datasets for city %{name}", name: name)
      }

  def metadata(TransportWeb.DatasetView, %{
        page_title: %{name: name},
        conn: %{params: %{"identifiant_offre" => _}}
      }),
      do: %{
        title: dgettext("seo", "Transport open datasets for transport offer %{name}", name: name)
      }

  def metadata(TransportWeb.DatasetView, %{page_title: %{type: type, name: name}}),
    do: %{
      title: dgettext("seo", "Transport open datasets for %{type} %{name}", type: type, name: name)
    }

  def metadata(TransportWeb.ResourceView, %{resource: %{format: format, title: title, dataset: dataset}}),
    do: %{
      title:
        dgettext("seo", "%{format} Transport open dataset - %{title} for %{custom_title} - %{territory}",
          custom_title: dataset.custom_title,
          territory: DB.Dataset.get_covered_area_or_nil(dataset),
          format: format,
          title: title
        )
    }

  def metadata(TransportWeb.StatsView, _),
    do: %{
      title: dgettext("seo", "State of transport open data in France")
    }

  def metadata(TransportWeb.AOMSView, _),
    do: %{
      title: dgettext("seo", "State of transport open data for french AOMs")
    }

  def metadata(TransportWeb.ReuserSpaceView, _),
    do: %{
      title: dgettext("seo", "Reuser space")
    }

  def metadata(_, %{live_module: TransportWeb.Live.OnDemandValidationSelectLive}),
    do: %{
      title: dgettext("seo", "Data quality evaluation")
    }

  def metadata(TransportWeb.ExploreView, %{page_title: page_title}) do
    %{title: page_title}
  end

  def metadata(TransportWeb.LandingPagesView, %{seo_page: "vls"}),
    do: %{
      title: "Jeux de données ouverts de la catégorie Vélos et trottinettes en libre-service"
    }

  def metadata(_view, _assigns), do: %{}
end
