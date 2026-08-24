defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_2_1 do
  @moduledoc """
  ResultsReader implementation for version 0.2.1.
  Delegates to V0_2_0, overriding only format_severity.
  """

  use Gettext, backend: TransportWeb.Gettext

  require Explorer.DataFrame, as: DF

  alias Transport.Validators.NeTEx.ResultsAdapters.Commons
  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_0
  alias Transport.Validators.NeTEx.ResultsReader
  alias Transport.Validators.NeTEx.ResultsWriter

  @behaviour ResultsReader
  @behaviour ResultsWriter

  @no_error "NoError"

  @categories_preferred_order [
    Commons.xsd_schema_category(),
    Commons.base_rules_category(),
    Commons.french_profile_category()
  ]

  @impl ResultsReader
  def format_severity(key, count) do
    case key do
      @no_error -> dgettext("netex-validator", "no error")
      _ -> V0_2_0.format_severity(key, count)
    end
  end

  @impl ResultsReader
  defdelegate get_issues(binary, filter, pagination_config), to: V0_2_0

  @impl ResultsReader
  defdelegate issue_type(list), to: V0_2_0

  @impl ResultsReader
  defdelegate no_error?(severity), to: V0_2_0

  @impl ResultsReader
  defdelegate summarize_xsd_errors(binary_result), to: V0_2_0

  @impl ResultsReader
  def french_profile_compliance_check, do: :partial

  @impl ResultsReader
  def french_profile, do: Transport.NeTEx.FrenchProfile.V1

  @impl ResultsReader
  def preferred_category_order, do: ["xsd-schema", "base-rules", "french-profile"]

  @impl ResultsWriter
  defdelegate count_max_severity(df), to: V0_2_0

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
    cond do
      String.starts_with?(code, "xsd-") -> Commons.xsd_schema_category()
      String.starts_with?(code, "pan:french_profile:") -> Commons.french_profile_category()
      true -> Commons.base_rules_category()
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
