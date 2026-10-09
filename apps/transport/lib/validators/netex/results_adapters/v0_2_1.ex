defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_1 do
  @moduledoc """
  ResultsAdapter implementation for version 0.2.1.
  """

  use Gettext, backend: TransportWeb.Gettext

  require Explorer.DataFrame, as: DF
  alias Transport.Validators.NeTEx.ResultsAdapters.Commons
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_0

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  @categories_preferred_order [
    Commons.xsd_schema_category(),
    Commons.base_rules_category(),
    Commons.french_profile_category()
  ]

  @doc """
  Returns the maximum issue severity found from a DataFrame.
  """
  @spec get_max_severity_error(Explorer.DataFrame.t()) :: binary()
  defdelegate get_max_severity_error(validation_result), to: V0_2_0

  # Delegation to V0_2_0 — these now accept DataFrames via the updated callbacks
  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_max_severity(validation_result), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate no_error?(severity), to: V0_2_0

  defdelegate severity_level(key), to: Commons

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate format_severity(key, count), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate count_by_category_and_severity(validation_result), to: V0_2_0

  # Internal helper used by digest/1 — no longer a public callback.
  defp count_by_severity(df), do: V0_2_0.count_by_severity(df)

  defp categorize(code) do
    cond do
      String.starts_with?(code, "xsd-") -> Commons.xsd_schema_category()
      String.starts_with?(code, "pan:french_profile:") -> Commons.french_profile_category()
      true -> Commons.base_rules_category()
    end
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate issue_type(list), to: V0_2_0

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
    results =
      if Commons.has_column?(df, "category") do
        df
        |> DF.filter(category == ^issues_category)
        |> Commons.count_and_slice(pagination_config)
      else
        {0, []}
      end

    {filter, results}
  end

  def get_issues(%Explorer.DataFrame{} = df, %{}, %Scrivener.Config{} = pagination_config) do
    default_category = pick_default_category(df)

    get_issues(df, %{"issues_category" => default_category}, pagination_config)
  end

  def get_issues(_, _, _), do: {%{"issues_category" => Commons.xsd_schema_category()}, {0, []}}

  defdelegate get_categories(df), to: V0_2_0

  def pick_default_category(%Explorer.DataFrame{} = df) do
    pick_default_category(df, @categories_preferred_order)
  end

  defdelegate pick_default_category(df, categories_preferred_order), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile_compliance_check, do: :partial

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile, do: Transport.NeTEx.FrenchProfile.V1

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def preferred_category_order, do: @categories_preferred_order

  @doc false
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def digest(%Explorer.DataFrame{} = df) do
    %{
      "stats" => count_by_severity(df),
      "max_severity" => count_max_severity(df)
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
  def to_binary_result(errors), do: Commons.to_binary_result(errors, &to_dataframe/1)

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate summarize_xsd_errors(binary_result), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summary_from_binary(binary_result) when is_binary(binary_result) do
    Commons.summary_from_binary(binary_result, @categories_preferred_order)
  end
end
