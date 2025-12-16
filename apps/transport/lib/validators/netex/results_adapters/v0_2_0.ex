defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_0 do
  @moduledoc """
  ResultsAdapter implementation for version 0.2.0.
  """

  use Gettext, backend: TransportWeb.Gettext

  require Explorer.DataFrame, as: DF
  alias Transport.Validators.NeTEx.ResultsAdapters.Commons
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
  Get issues from validation results, filtered on category, and paginated.
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def get_issues(binary, %{} = filter, %Scrivener.Config{} = pagination_config) when is_binary(binary) do
    binary
    |> Commons.from_binary()
    |> get_issues(filter, pagination_config)
  end

  def get_issues(
        %Explorer.DataFrame{} = df,
        %{"issues_category" => issues_category} = filter,
        %Scrivener.Config{} = pagination_config
      ) do
    {filter,
     df
     |> DF.filter(category == ^issues_category)
     |> order_issues_by_location()
     |> Commons.count_and_slice(pagination_config)}
  end

  def get_issues(%Explorer.DataFrame{} = df, %{}, %Scrivener.Config{} = pagination_config) do
    default_category = pick_default_category(df)

    get_issues(df, %{"issues_category" => default_category}, pagination_config)
  end

  def get_issues(_, _, _), do: {%{"issues_category" => @xsd_schema_category}, {0, []}}

  def pick_default_category(%Explorer.DataFrame{} = df), do: pick_default_category(df, @categories_preferred_order)

  def pick_default_category(%Explorer.DataFrame{} = df, categories_preferred_order) do
    categories = get_categories(df)

    ordered_categories = categories_preferred_order |> Enum.with_index() |> Map.new()

    categories |> Enum.sort_by(&ordered_categories[&1]) |> List.first()
  end

  def get_categories(%Explorer.DataFrame{} = df), do: Commons.get_values(df, "category")

  defdelegate order_issues_by_location(issues), to: V0_1_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate french_profile_compliance_check(), to: V0_1_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def digest(validation_result) do
    %{
      "summary" => summary(validation_result),
      "stats" => count_by_severity(validation_result),
      "max_severity" => count_max_severity(validation_result)
    }
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def to_dataframe(errors) do
    Commons.to_dataframe(errors, &build_synthetic_attributes/1)
  end

  defp build_synthetic_attributes(mandatory_attributes) do
    %{
      "category" => categorize(mandatory_attributes["code"])
    }
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def to_binary_result(result) do
    result
    |> Map.values()
    |> List.flatten()
    |> to_dataframe()
    |> Commons.to_binary()
  end
end
