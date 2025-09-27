defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_1 do
  @moduledoc """
  ResultsAdapter implementation for version 0.2.1.
  """

  use Gettext, backend: TransportWeb.Gettext

  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_0

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  @no_error "NoError"

  @unknown_code "unknown-code"

  @xsd_schema_category "xsd-schema"

  @french_profile_category "french-profile"

  @base_rules_category "base-rules"

  @categories_preferred_order [
    @xsd_schema_category,
    @french_profile_category,
    @base_rules_category
  ]

  @spec get_max_severity_error(map()) :: binary()
  defdelegate get_max_severity_error(validation_result), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_max_severity(validation_result), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate no_error?(severity), to: V0_2_0

  @spec severity_level(binary()) :: integer()
  defdelegate severity_level(key), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate format_severity(key, count), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_by_severity(validation_result), to: V0_2_0

  @doc """
  iex> index_messages([])
  %{}

  iex> index_messages([%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}, %{"code"=>"pan:french_profile:123", "id"=> 1}, %{"code"=>"b", "id"=> 3}])
  %{"xsd-schema"=>[%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}], "french-profile"=>[%{"code"=>"pan:french_profile:123", "id"=> 1}], "base-rules"=>[%{"code"=>"b", "id"=> 3}]}

  Sometimes the message has no code
  iex> index_messages([%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}, %{"id"=> 3}])
  %{"xsd-schema"=>[%{"code"=>"xsd-123", "id"=> 1}, %{"code"=>"xsd-456", "id"=> 2}], "base-rules"=>[%{"id"=> 3}]}
  """
  def index_messages(messages), do: Enum.group_by(messages, &index_message/1)

  def index_message(message), do: message |> get_code() |> categorize()

  defp categorize(code) do
    cond do
      String.starts_with?(code, "xsd-") -> @xsd_schema_category
      String.starts_with?(code, "pan:french_profile:") -> @french_profile_category
      true -> @base_rules_category
    end
  end

  defp get_code(%{"code" => code}), do: code
  defp get_code(%{}), do: @unknown_code

  @doc """
  iex> validation_result = %{"xsd-schema" => [%{"code" => "xsd-123", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "french-profile"=>[%{"code"=>"pan:french_profile:123", "criticity" => "error"}], "base-rules" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}]}
  iex> summary(validation_result)
  [
    {"xsd-schema", %{count: 1, criticity: "error"}},
    {"french-profile", %{count: 1, criticity: "error"}},
    {"base-rules", %{count: 1, criticity: "error"}}
  ]
  iex> summary(%{})
  [
    {"xsd-schema", %{count: 0, criticity: "NoError"}},
    {"french-profile", %{count: 0, criticity: "NoError"}},
    {"base-rules", %{count: 0, criticity: "NoError"}}
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
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate issue_type(list), to: V0_2_0

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

  defdelegate order_issues_by_location(issues), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile_compliance_check, do: :partial
end
