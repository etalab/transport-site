defmodule TransportWeb.SeoMetadata do
  @moduledoc """
  Module to set a title and a description for each pages.
  The default title/description are defined in app.html.eex
  """
  import TransportWeb.Gettext

  @spec metadata(any()) :: %{optional(:title) => binary(), optional(:description) => binary()}
  def metadata(%{view_module: TransportWeb.DatasetView, q: q}) when not is_nil(q),
    do: %{
      title: dgettext("seo", "%{q}: Available transport open datasets", q: q)
    }

  def metadata(%{view_module: TransportWeb.DatasetView, dataset: dataset}) do
    formats =
      case DB.Dataset.formats(dataset) do
        [] -> ""
        l -> " (#{Enum.join(l, ", ")})"
      end

    %{
      title:
        dgettext("seo", "%{spatial} - Open %{formats} datasets - %{territory}",
          spatial: dataset.spatial,
          territory: DB.Dataset.get_territory_or_nil(dataset),
          formats: formats
        )
    }
  end

  def metadata(%{view_module: TransportWeb.DatasetView, page_title: %{type: "AOM", name: name}}),
    do: %{
      title: dgettext("seo", "%{name} AOM: Transport open datasets ", name: name)
    }

  def metadata(%{
        view_module: TransportWeb.DatasetView,
        page_title: %{name: name},
        conn: %{params: %{"insee_commune" => _}}
      }),
      do: %{
        title: dgettext("seo", "Transport open datasets for city %{name}", name: name)
      }

  def metadata(%{view_module: TransportWeb.DatasetView, page_title: %{type: type, name: name}}),
    do: %{
      title: dgettext("seo", "Transport open datasets for %{type} %{name}", type: type, name: name)
    }

  def metadata(%{view_module: TransportWeb.ResourceView, resource: %{format: format, title: title, dataset: dataset}}),
    do: %{
      title:
        dgettext("seo", "%{format} Transport open dataset - %{title} for %{spatial} - %{territory}",
          spatial: dataset.spatial,
          territory: DB.Dataset.get_territory_or_nil(dataset),
          format: format,
          title: title
        )
    }

  def metadata(%{view_module: TransportWeb.StatsView}),
    do: %{
      title: dgettext("seo", "State of transport open data in France")
    }

  def metadata(%{view_module: TransportWeb.AOMSView}),
    do: %{
      title: dgettext("seo", "State of transport open data for french AOMs")
    }

  def metadata(%{view_module: TransportWeb.PageView, page: "real_time.html"}),
    do: %{
      title: dgettext("seo", "Non standard real time transport open data")
    }

  def metadata(%{view_module: TransportWeb.ValidationView}),
    do: %{
      title: dgettext("seo", "GTFS data quality evaluation")
    }

  def metadata(_),
    do: %{}
end
