defmodule DB.Validation do
  @moduledoc """
  Validation model
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.Resource
  import DB.Gettext, only: [dgettext: 2]

  typed_schema "validations" do
    field(:details, :map)
    field(:date, :string)

    belongs_to(:resource, Resource)
  end

  @spec severities_map() :: map()
  def severities_map,
    do: %{
      "Fatal" => %{level: 0, text: dgettext("validations", "Fatal failures")},
      "Error" => %{level: 1, text: dgettext("validations", "Errors")},
      "Warning" => %{level: 2, text: dgettext("validations", "Warnings")},
      "Information" => %{level: 3, text: dgettext("validations", "Informations")},
      "Irrelevant" => %{level: 4, text: dgettext("validations", "Passed validations")}
    }

  @spec severities(binary()) :: %{level: integer(), text: binary()}
  def severities(key), do: severities_map()[key]

  @spec get_issues(%{details: any()}, map()) :: [any()]
  def get_issues(%{details: nil}, _), do: []
  def get_issues(%{details: validations}, %{"issue_type" => issue_type}), do: Map.get(validations, issue_type, [])
  def get_issues(%{details: validations}, _) when validations == %{}, do: []

  def get_issues(%{details: validations}, _) do
    validations
    |> Map.values()
    |> Enum.sort_by(fn [%{"severity" => severity} | _] -> severities(severity).level end)
    |> List.first()
  end

  @spec summary(map()) :: keyword()
  def summary(%{details: issues}) do
    existing_issues =
      issues
      |> Enum.map(fn {key, issues} ->
        {key,
         %{
           count: Enum.count(issues),
           title: Resource.issues_short_translation()[key],
           severity: issues |> List.first() |> Map.get("severity")
         }}
      end)
      |> Map.new()

    Resource.issues_short_translation()
    |> Enum.map(fn {key, title} -> {key, %{count: 0, title: title, severity: "Irrelevant"}} end)
    |> Map.new()
    |> Map.merge(existing_issues)
    |> Enum.group_by(fn {_, issue} -> issue.severity end)
    |> Enum.sort_by(fn {severity, _} -> severities(severity).level end)
  end

  @doc """
  Returns the number of issues by severity level
  """
  @spec count_by_severity(map()) :: map()
  def count_by_severity(validation) do
    case validation do
      %{details: issues} ->
        issues
        |> Enum.flat_map(fn {_, v} -> v end)
        |> Enum.reduce(%{}, fn v, acc -> Map.update(acc, v["severity"], 1, &(&1 + 1)) end)

      _ ->
        %{}
    end
  end
end
