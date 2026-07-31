defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_0 do
  @moduledoc """
  ResultsReader implementation for version 0.2.0.
  Delegates to V0_1_0, overriding format_severity and summarize_xsd_errors.
  """

  use Gettext, backend: TransportWeb.Gettext

  require Explorer.DataFrame, as: DF

  alias Transport.Validators.NeTEx.ResultsAdapters.Commons
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_1_0
  alias Transport.Validators.NeTEx.ResultsReader
  alias Transport.Validators.NeTEx.ResultsWriter

  @behaviour ResultsReader
  @behaviour ResultsWriter

  @no_error "NoError"

  @categories_preferred_order [
    Commons.xsd_schema_category(),
    Commons.base_rules_category()
  ]

  @impl ResultsReader
  def format_severity(key, count) do
    case key do
      @no_error -> dgettext("netex-validator", "no error")
      _ -> V0_1_0.format_severity(key, count)
    end
  end

  @doc """
  Get issues from validation results, filtered on category, and paginated.
  """
  @impl ResultsReader
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

  defp pick_default_category(%Explorer.DataFrame{} = df), do: pick_default_category(df, @categories_preferred_order)

  defp pick_default_category(%Explorer.DataFrame{} = df, categories_preferred_order) do
    categories = get_categories(df)

    ordered_categories = categories_preferred_order |> Enum.with_index() |> Map.new()

    default_category = categories |> Enum.sort_by(&ordered_categories[&1]) |> List.first()

    default_category || Commons.xsd_schema_category()
  end

  defp get_categories(%Explorer.DataFrame{} = df), do: Commons.get_values(df, "category")

  defp order_issues_by_location(%Explorer.DataFrame{} = df) do
    DF.sort_by(df, &[&1["resource.filename"], &1["resource.line"], &1["message"]])
  end

  @impl ResultsReader
  defdelegate issue_type(list), to: V0_1_0

  @impl ResultsReader
  defdelegate no_error?(severity), to: V0_1_0

  @impl ResultsReader
  def summarize_xsd_errors(binary_result) do
    df = Commons.from_binary(binary_result)

    if Commons.has_column?(df, "category") do
      df
      |> DF.filter(category == ^Commons.xsd_schema_category())
      |> Commons.summarize_xsd_errors()
    else
      []
    end
  end

  @impl ResultsReader
  def french_profile_compliance_check, do: :none

  @impl ResultsReader
  def french_profile, do: nil

  @impl ResultsReader
  def preferred_category_order, do: ["xsd-schema", "base-rules"]

  @impl ResultsWriter
  defdelegate count_max_severity(df), to: V0_1_0

  @impl ResultsWriter
  def digest(%Explorer.DataFrame{} = df) do
    %{
      "summary" => summary(df),
      "stats" => count_by_severity(df),
      "max_severity" => count_max_severity(df)
    }
  end

  defp summary(%Explorer.DataFrame{} = df) do
    @categories_preferred_order
    |> Enum.map(fn category ->
      cat_df = DF.filter(df, category == ^category)
      count = DF.n_rows(cat_df)
      worst_criticity = Commons.get_worst_criticity(cat_df, count)

      %{"category" => category, "stats" => %{"count" => count, "criticity" => worst_criticity}}
    end)
  end

  defp count_by_severity(%Explorer.DataFrame{} = df) do
    if DF.n_rows(df) == 0 do
      %{"max_level" => @no_error, "worst_occurrences" => 0}
    else
      df
      |> DF.frequencies([:criticity])
      |> DF.to_rows()
      |> Enum.map(fn %{"criticity" => k, "counts" => v} -> {k, v} end)
      |> Map.new()
    end
  end

  @impl ResultsWriter
  def to_dataframe(errors) do
    Commons.to_dataframe(errors, &build_synthetic_attributes/1)
  end

  defp build_synthetic_attributes(mandatory_attributes) do
    %{"category" => categorize(mandatory_attributes["code"])}
  end

  defp categorize(code) do
    if String.starts_with?(code, "xsd-") do
      Commons.xsd_schema_category()
    else
      Commons.base_rules_category()
    end
  end

  @impl ResultsWriter
  def to_binary_result(errors) do
    errors
    |> to_dataframe()
    |> Commons.to_binary()
  end

  @impl ResultsWriter
  def get_max_severity_error(df) do
    %{"max_level" => severity} = count_max_severity(df)
    severity
  end
end
