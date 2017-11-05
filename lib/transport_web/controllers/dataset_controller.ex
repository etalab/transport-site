defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData
  alias Transport.Datagouvfr.Client.Datasets
  alias Transport.Datagouvfr.Authentication

  def index(conn, _) do
    conn
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end

  def details(conn, %{"slug" => slug}) do
    slug
    |> ReusableData.get_dataset(:with_celery_task)
    |> case do
      nil    -> render conn, "error.html"
      dataset -> conn
                 |> assign(:dataset, dataset)
                 |> assign(:nb_errors, count_errors(dataset))
                 |> assign(:nb_warnings, count_warnings(dataset))
                 |> assign(:nb_notices, count_notices(dataset))
                 |> assign(:datasetid, get_dataset_id(conn, dataset))
                 |> assign(:datagouvfrsite,
                      Application.get_env(:oauth2, Authentication)[:site])
                 |> render("details.html")
    end
  end

#private functions

  defp get_dataset_id(conn, dataset) do
    conn
    |> Datasets.get(dataset.slug)
    |> case do
      {:ok, d}    -> d["id"]
      {:error, _} -> nil
    end
  end

  defp count_errors(dataset) do
    dataset.celery_task.result
    |> Map.get("validations")
    |> Map.get("errors")
    |> Enum.count()
  end

  defp count_warnings(dataset) do
    dataset.celery_task.result
    |> Map.get("validations")
    |> Map.get("warnings")
    |> Enum.count()
  end

  defp count_notices(dataset) do
    dataset.celery_task.result
    |> Map.get("validations")
    |> Map.get("notices")
    |> Enum.count()
  end
end
