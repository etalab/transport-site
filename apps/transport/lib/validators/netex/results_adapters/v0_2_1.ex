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
  defdelegate count_by_severity(validation_result), to: V0_2_0

  defp categorize(code) do
    cond do
      String.starts_with?(code, "xsd-") -> Commons.xsd_schema_category()
      String.starts_with?(code, "pan:french_profile:") -> Commons.french_profile_category()
      true -> Commons.base_rules_category()
    end
  end

  @doc """
  Builds a category-based summary from a DataFrame.

  ## Examples

      iex> errors = [%{"code" => "xsd-1", "criticity" => "error"}, %{"code" => "pan:french_profile:1", "criticity" => "error"}, %{"code" => "b", "criticity" => "error"}]
      iex> df = to_dataframe(errors)
      iex> summary(df)
      [
        %{"category" => "xsd-schema", "stats" => %{"count" => 1, "criticity" => "error"}},
        %{"category" => "base-rules", "stats" => %{"count" => 1, "criticity" => "error"}},
        %{"category" => "french-profile", "stats" => %{"count" => 1, "criticity" => "error"}}
      ]

      iex> df = Explorer.DataFrame.new([category: [], code: [], criticity: []], dtypes: [category: :category, code: :category, criticity: :category])
      iex> summary(df)
      [
        %{"category" => "xsd-schema", "stats" => %{"count" => 0, "criticity" => "NoError"}},
        %{"category" => "base-rules", "stats" => %{"count" => 0, "criticity" => "NoError"}},
        %{"category" => "french-profile", "stats" => %{"count" => 0, "criticity" => "NoError"}}
      ]
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summary(%Explorer.DataFrame{} = df) do
    @categories_preferred_order
    |> Enum.map(fn category ->
      cat_df = DF.filter(df, category == ^category)
      count = DF.n_rows(cat_df)
      worst_criticity = Commons.get_worst_criticity(cat_df, count)

      %{"category" => category, "stats" => %{"count" => count, "criticity" => worst_criticity}}
    end)
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
        |> order_issues_by_location()
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

  defdelegate order_issues_by_location(issues), to: V0_2_0

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile_compliance_check, do: :partial

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile, do: Transport.NeTEx.FrenchProfile.V1

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def preferred_category_order, do: @categories_preferred_order

  @doc """
  Builds a digest map from a DataFrame.
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def digest(%Explorer.DataFrame{} = df) do
    %{
      "summary" => summary(df),
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

  @doc """
  Converts raw error list directly to a parquet binary — no intermediate grouping.
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def to_binary_result(errors) do
    errors
    |> to_dataframe()
    |> Commons.to_binary()
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  defdelegate summarize_xsd_errors(binary_result), to: V0_2_0
end
