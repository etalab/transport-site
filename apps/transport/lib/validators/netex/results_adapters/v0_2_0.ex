defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_0 do
  @moduledoc """
  ResultsAdapter implementation for version 0.2.0.
  """

  use Gettext, backend: TransportWeb.Gettext

  alias Transport.Validators.NeTEx.ResultsAdapters.V0_1_0

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  @no_error "NoError"

  @unknown_code "unknown-code"

  @xsd_schema_category "xsd-schema"

  @base_rules_category "base-rules"

  @categories_preferred_order [
    @xsd_schema_category,
    @base_rules_category
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
    %{"max_level" => severity} = validation_result |> count_max_severity()
    severity
  end

  @doc """
  Returns the maximum severity, with the issues count

  iex> validation_result = %{"xsd-schema" => [%{"criticity" => "error"}], "french-profile" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  %{"max_level" => "error", "worst_occurrences" => 2}
  iex> validation_result = %{"french-profile" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  %{"max_level" => "warning", "worst_occurrences" => 1}
  iex> count_max_severity(%{})
  %{"max_level" => "NoError", "worst_occurrences" => 0}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_max_severity(validation_result), to: V0_1_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate no_error?(severity), to: V0_1_0

  @spec severity_level(binary()) :: integer()
  defdelegate severity_level(key), to: V0_1_0

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
      @no_error -> dgettext("netex-validator", "no error")
      _ -> V0_1_0.format_severity(key, count)
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
  defdelegate count_by_severity(validation_result), to: V0_1_0

  @doc """
  iex> index_messages([])
  %{}

  iex> index_messages([%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}, %{"code"=>"b", "id"=> 3}])
  %{"xsd-schema"=>[%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}], "base-rules"=>[%{"code"=>"b", "id"=> 3}]}

  Sometimes the message has no code
  iex> index_messages([%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}, %{"id"=> 3}])
  %{"xsd-schema"=>[%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}], "base-rules"=>[%{"id"=> 3}]}
  """
  def index_messages(messages), do: Enum.group_by(messages, &index_message/1)

  def index_message(message), do: message |> get_code() |> categorize()

  defp categorize(code) do
    if String.starts_with?(code, "xsd-") do
      @xsd_schema_category
    else
      @base_rules_category
    end
  end

  defp get_code(%{"code" => code}), do: code
  defp get_code(%{}), do: @unknown_code

  @doc """
  iex> validation_result = %{"xsd-schema" => [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "base-rules" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}]}
  iex> summary(validation_result)
  [
    %{"category" => "xsd-schema", "stats" => %{"count" => 1, "criticity" => "error"}},
    %{"category" => "base-rules", "stats" => %{"count" => 1, "criticity" => "error"}}
  ]
  iex> summary(%{})
  [
    %{"category" => "xsd-schema", "stats" => %{"count" => 0, "criticity" => "NoError"}},
    %{"category" => "base-rules", "stats" => %{"count" => 0, "criticity" => "NoError"}}
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

      stats = %{"count" => length(errors), "criticity" => worst_criticity}

      %{"category" => category, "stats" => stats}
    end)
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate issue_type(list), to: V0_1_0

  @doc """
  Get issues from validation results. For a specific issue type if specified, or the most severe.

  iex> validation_result = %{"xsd-schema" => [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "base-rules" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}]}
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
    |> Map.get(category || @xsd_schema_category, [])
  end

  defdelegate order_issues_by_location(issues), to: V0_1_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate french_profile_compliance_check(), to: V0_1_0
end
