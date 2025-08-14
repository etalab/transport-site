defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_0 do
  @moduledoc """
  ResultsAdapter implementation for version 0.2.0.
  """

  use Gettext, backend: TransportWeb.Gettext

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  @no_error "NoError"

  @unknown_code "unknown-code"

  @xsd_category "xsd-schema"

  @catch_all_category "no-category"

  @categories_preferred_order [
    @xsd_category,
    @catch_all_category
  ]

  @doc """
  Returns the maximum issue severity found

  iex> validation_result = %{"uic-operating-period" => [%{"criticity" => "error"}], "valid-day-bits" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "error"}]}
  iex> get_max_severity_error(validation_result)
  "error"

  iex> get_max_severity_error(%{})
  "NoError"
  """
  @spec get_max_severity_error(map()) :: binary()
  def get_max_severity_error(validation_result) do
    {severity, _} = validation_result |> count_max_severity()
    severity
  end

  @doc """
  Returns the maximum severity, with the issues count

  iex> validation_result = %{"xsd-schema" => [%{"criticity" => "error"}], "french-profile" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  {"error", 2}
  iex> validation_result = %{"french-profile" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  {"warning", 1}
  iex> count_max_severity(%{})
  {"NoError", 0}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_max_severity(validation_result) when validation_result == %{} do
    {@no_error, 0}
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_max_severity(%{} = validation_result) do
    validation_result
    |> count_by_severity()
    |> Enum.min_by(fn {severity, _count} -> severity |> severity_level() end)
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def no_error?(severity), do: @no_error == severity

  @spec severity_level(binary()) :: integer()
  defp severity_level(key) do
    case key do
      "error" -> 1
      "warning" -> 2
      "information" -> 3
      _ -> 4
    end
  end

  @doc """
  iex> Gettext.put_locale("en")
  iex> format_severity("error", 1)
  "1 error"
  iex> format_severity("error", 2)
  "2 errors"
  iex> format_severity("NoError", 0)
  "no error"
  iex> Gettext.put_locale("fr")
  iex> format_severity("error", 1)
  "1 erreur"
  iex> format_severity("error", 2)
  "2 erreurs"
  iex> format_severity("NoError", 0)
  "aucune erreur"
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def format_severity(key, count) do
    case key do
      "error" -> dngettext("netex-validator", "error", "errors", count)
      "warning" -> dngettext("netex-validator", "warning", "warnings", count)
      "information" -> dngettext("netex-validator", "information", "informations", count)
      @no_error -> dgettext("netex-validator", "no error")
    end
  end

  @doc """
  Returns the number of issues by severity level

  iex> validation_result = %{"uic-operating-period" => [%{"criticity" => "warning"}], "valid-day-bits" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "error"}]}
  iex> count_by_severity(validation_result)
  %{"warning" => 1, "error" => 2}

  iex> count_by_severity(%{})
  %{}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_by_severity(%{} = validation_result) do
    validation_result
    |> Enum.flat_map(fn {_, v} -> v end)
    |> Enum.reduce(%{}, fn v, acc -> Map.update(acc, v["criticity"], 1, &(&1 + 1)) end)
  end

  def count_by_severity(_), do: %{}

  @doc """
  iex> index_messages([])
  %{}

  iex> index_messages([%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}, %{"code"=>"b", "id"=> 3}])
  %{"xsd-schema"=>[%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}], "no-category"=>[%{"code"=>"b", "id"=> 3}]}

  Sometimes the message has no code
  iex> index_messages([%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}, %{"id"=> 3}])
  %{"xsd-schema"=>[%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}], "no-category"=>[%{"id"=> 3}]}
  """
  def index_messages(messages), do: Enum.group_by(messages, &index_message/1)

  def index_message(message), do: message |> get_code() |> categorize()

  defp categorize(code) do
    if String.starts_with?(code, "xsd-") do
      @xsd_category
    else
      @catch_all_category
    end
  end

  defp get_code(%{"code" => code}), do: code
  defp get_code(%{}), do: @unknown_code

  @doc """
  iex> validation_result = %{"xsd-schema" => [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "no-category" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}]}
  iex> summary(validation_result)
  [
    {"xsd-schema", %{count: 1, criticity: "error"}},
    {"no-category", %{count: 1, criticity: "error"}}
  ]
  iex> summary(%{})
  [
    {"xsd-schema", %{count: 0, criticity: "NoError"}},
  ]
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summary(%{} = validation_result) do
    @categories_preferred_order
    |> Enum.map(fn category ->
      errors = validation_result |> Map.get(category, [])

      worst_criticity =
        errors
        |> Enum.map(fn error -> Map.get(error, "criticity", @no_error) end)
        |> Enum.min_by(&severity_level/1, fn -> @no_error end)

      stats = %{count: length(errors), criticity: worst_criticity}

      {category, stats}
    end)
    |> Enum.reject(fn {category, %{count: count}} ->
      category == @catch_all_category && count == 0
    end)
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def issue_type([]), do: nil
  def issue_type([h | _]), do: h["code"] || @unknown_code

  @doc """
  Get issues from validation results. For a specific issue type if specified, or the most severe.

  iex> validation_result = %{"xsd-schema" => [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "no-category" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}]}
  iex> get_issues(validation_result, %{"issues_category" => "xsd-schema"})
  [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}]
  iex> get_issues(validation_result, %{"issues_category" => "broken-file"})
  []
  iex> get_issues(validation_result, nil)
  [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}]
  iex> get_issues(%{}, nil)
  []
  iex> get_issues([], nil)
  []
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def get_issues(%{} = validation_result, %{"issues_category" => issues_category}) do
    validation_result
    |> Map.get(issues_category, [])
    |> order_issues_by_location()
  end

  def get_issues(%{} = validation_result, _) do
    validation_result
    |> pick_preferred_category()
    |> order_issues_by_location()
  end

  def get_issues(_, _), do: []

  defp pick_preferred_category(%{} = validation_result) do
    category =
      @categories_preferred_order
      |> Enum.find(fn category -> not is_nil(validation_result[category]) end)

    validation_result
    |> Map.get(category || @catch_all_category, [])
  end

  defp order_issues_by_location(issues) do
    issues
    |> Enum.sort_by(fn issue ->
      message = Map.get(issue, "message", "")
      resource = Map.get(issue, "resource", %{})
      filename = Map.get(resource, "filename", "")
      line = Map.get(resource, "line", "")
      {filename, line, message}
    end)
  end
end
