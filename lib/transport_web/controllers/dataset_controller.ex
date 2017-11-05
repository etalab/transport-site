defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData

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
                 |> render("details.html")
    end
  end

#private functions

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
