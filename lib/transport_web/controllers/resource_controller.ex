defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Transport.{Repo, Resource, Validation}

  def details(conn, params) do
    config = make_pagination_config(params)
    id = params["id"]

    case Repo.get(Resource, id) do
      nil -> render(conn, "404.html")
      resource ->
        resource_with_dataset = resource |> Repo.preload([:dataset, :validation])
        dataset = resource_with_dataset.dataset |> Repo.preload([:resources])
        other_resources =
          dataset.resources
          |> Stream.reject(&(Integer.to_string(&1.id) == id))
          |> Stream.filter(&Resource.valid?/1)
          |> Enum.to_list()

        issue_type = get_issue_type(params, resource_with_dataset.validation)
        issues = get_issues(resource_with_dataset.validation, issue_type, config)

        issue_types = for {key, _} <- Resource.issues_short_translation,
          into: %{},
          do: {key, count_issues(resource_with_dataset.validation, key)}

        render(
          conn,
          "details.html",
          %{resource: resource_with_dataset,
           other_resources: other_resources,
           dataset: dataset,
           issue_types: issue_types,
           issue_type: issue_type,
           issues_short_translation: Resource.issues_short_translation,
           issues: issues}
        )
    end
  end

  defp get_issue_type(%{"issue_type" => issue_type}, _), do: issue_type
  defp get_issue_type(_, %Validation{details: validations}) when validations != nil and validations != %{} do
    {issue_type, _issues} = validations |> Map.to_list() |> List.first()
    issue_type
  end
  defp get_issue_type(_, _), do: nil

  defp get_issues(%{details: validations}, issue_type, config) when validations != nil do
    validations
    |> Map.get(issue_type,  [])
    |> Scrivener.paginate(config)
  end
  defp get_issues(_, _, _), do: []

  defp count_issues(%{details: validations}, issue_type) when validations != nil do
    validations
    |> Map.get(issue_type, [])
    |> Enum.count
  end
  defp count_issues(_, _), do: 0
end
