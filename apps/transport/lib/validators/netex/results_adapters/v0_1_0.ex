defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_1_0 do
  @moduledoc """
  Helper module to build and interpret results for NeTEx validation prior to 0.2.0.
  """

  use Gettext, backend: TransportWeb.Gettext

  require Explorer.DataFrame, as: DF
  alias Transport.Validators.NeTEx.ResultsAdapters.Commons

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  @no_error "NoError"

  @unknown_code "unknown-code"

  @categories_preferred_order [
    Commons.xsd_schema_category(),
    Commons.base_rules_category()
  ]

  @doc """
  Returns the maximum severity, with the issues count.

  ## Examples

      iex> errors = [%{"criticity" => "error"}, %{"criticity" => "error"}, %{"criticity" => "warning"}]
      iex> df = to_dataframe(errors)
      iex> count_max_severity(df)
      %{"max_level" => "error", "worst_occurrences" => 2}

      iex> errors = [%{"criticity" => "warning"}]
      iex> df = to_dataframe(errors)
      iex> count_max_severity(df)
      %{"max_level" => "warning", "worst_occurrences" => 1}

      iex> df = Explorer.DataFrame.new(code: [])
      iex> count_max_severity(df)
      %{"max_level" => "NoError", "worst_occurrences" => 0}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_max_severity(%Explorer.DataFrame{} = df) do
    case DF.n_rows(df) do
      0 ->
        %{"max_level" => @no_error, "worst_occurrences" => 0}

      _ ->
        {max_level, worst_occurrences} =
          count_by_severity(df)
          |> Enum.filter(fn {_severity, count} -> count > 0 end)
          |> Enum.min_by(fn {severity, _count} -> severity_level(severity) end)

        %{"max_level" => max_level, "worst_occurrences" => worst_occurrences}
    end
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def no_error?(severity), do: @no_error == severity

  defdelegate severity_level(key), to: Commons

  @doc """
  iex> Gettext.put_locale("en")
  iex> format_severity("error", 1)
  "1 error"
  iex> format_severity("error", 2)
  "2 errors"
  iex> Gettext.put_locale("fr")
  iex> format_severity("error", 1)
  "1 erreur"
  iex> format_severity("error", 2)
  "2 erreurs"
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def format_severity(key, count) do
    case key do
      "error" ->
        dngettext("netex-validator", "error", "errors", count,
          value: Helpers.format_number(count, locale: Gettext.get_locale())
        )

      "warning" ->
        dngettext("netex-validator", "warning", "warnings", count,
          value: Helpers.format_number(count, locale: Gettext.get_locale())
        )

      "information" ->
        dngettext("netex-validator", "information", "informations", count,
          value: Helpers.format_number(count, locale: Gettext.get_locale())
        )
    end
  end

  @doc """
  Returns the number of issues by severity level from a DataFrame.

  ## Examples

      iex> errors = [%{"criticity" => "warning"}, %{"criticity" => "error"}, %{"criticity" => "error"}]
      iex> df = to_dataframe(errors)
      iex> count_by_severity(df)
      %{"warning" => 1, "error" => 2}

      iex> df = Explorer.DataFrame.new(code: [], criticity: [])
      iex> count_by_severity(df)
      %{}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_by_severity(%Explorer.DataFrame{} = df) do
    if DF.n_rows(df) == 0 do
      %{}
    else
      df
      |> DF.frequencies([:criticity])
      |> DF.to_rows()
      |> Enum.map(fn %{"criticity" => k, "counts" => v} -> {k, v} end)
      |> Map.new()
    end
  end

  @doc """
  Builds a severity-based summary from a DataFrame.

  Returns items grouped by criticity (error/warning/information), as expected by the v0_1.0 template.

  ## Examples

      iex> errors = [%{"code" => "xsd-1", "criticity" => "error"}, %{"code" => "b", "criticity" => "warning"}]
      iex> df = to_dataframe(errors)
      iex> summary(df) |> Enum.map(& &1["severity"])
      ["error", "warning"]

      iex> df = Explorer.DataFrame.new(code: [], criticity: [])
      iex> summary(df)
      []
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summary(%Explorer.DataFrame{} = df) do
    errors = DF.to_rows(df)

    if Enum.empty?(errors) do
      []
    else
      errors
      |> Enum.group_by(& &1["code"])
      |> Enum.map(fn {code, errs} ->
        {
          code,
          %{
            "count" => length(errs),
            "criticity" => hd(errs) |> Map.get("criticity"),
            "title" => issues_short_translation_per_code(code)
          }
        }
      end)
      |> Enum.group_by(fn {_, details} -> details["criticity"] end)
      |> Enum.sort_by(fn {criticity, _} -> severity_level(criticity) end)
      |> Enum.map(fn {severity, issues} ->
        %{
          "severity" => severity,
          "issues" => issues |> Enum.map(fn {key, issue} -> %{"key" => key, "issue" => issue} end)
        }
      end)
    end
  end

  @spec issues_short_translation_per_code(binary()) :: binary()
  defp issues_short_translation_per_code(code) do
    if String.starts_with?(code, "xsd-") do
      dgettext("netex-validator", "XSD validation")
    else
      Map.get(issues_short_translation(), code, code)
    end
  end

  @spec issues_short_translation() :: %{binary() => binary()}
  defp issues_short_translation,
    do: %{
      "composite-frame-ligne-mandatory" => dgettext("netex-validator", "Composite frame ligne mandatory"),
      "frame-arret-resources" => dgettext("netex-validator", "Frame arret resources"),
      "frame-calendrier-resources" => dgettext("netex-validator", "Frame calendrier resources"),
      "frame-horaire-resources" => dgettext("netex-validator", "Frame horaire resources"),
      "frame-ligne-resources" => dgettext("netex-validator", "Frame ligne resources"),
      "frame-reseau-resources" => dgettext("netex-validator", "Frame reseau resources"),
      "latitude-mandatory" => dgettext("netex-validator", "Latitude mandatory"),
      "longitude-mandatory" => dgettext("netex-validator", "Longitude mandatory"),
      "uic-operating-period" => dgettext("netex-validator", "UIC operating period"),
      "valid-day-bits" => dgettext("netex-validator", "Valid day bits"),
      "version-any" => dgettext("netex-validator", "Version any"),
      @unknown_code => dgettext("netex-validator", "Unspecified error")
    }

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def issue_type([]), do: nil
  def issue_type([h | _]), do: h["code"] || @unknown_code

  @doc """
  Get issues from validation results. For a specific issue type if specified, or the most severe.
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def get_issues(binary, %{} = filter, %Scrivener.Config{} = pagination_config) when is_binary(binary) do
    binary
    |> Commons.from_binary()
    |> get_issues(filter, pagination_config)
  end

  def get_issues(
        %Explorer.DataFrame{} = df,
        %{"issue_type" => issue_type} = filter,
        %Scrivener.Config{} = pagination_config
      ) do
    results =
      if Commons.has_column?(df, "code") do
        df
        |> DF.filter(code == ^issue_type)
        |> Commons.count_and_slice(pagination_config)
      else
        {0, []}
      end

    {filter, results}
  end

  def get_issues(%Explorer.DataFrame{} = df, %{}, %Scrivener.Config{} = pagination_config) do
    filter = %{"issue_type" => pick_default_issue_type(df)}

    get_issues(df, filter, pagination_config)
  end

  def get_issues(_, _, _), do: {%{"issue_type" => ""}, {0, []}}

  def pick_default_issue_type(%Explorer.DataFrame{} = df) do
    get_codes(df) |> List.first() || ""
  end

  def get_codes(%Explorer.DataFrame{} = df), do: Commons.get_values(df, "code")

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile_compliance_check, do: :none

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile, do: nil

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def preferred_category_order, do: @categories_preferred_order

  @doc """
  Builds a digest map from a DataFrame.

  ## Examples

      iex> errors = [%{"code" => "xsd-1", "criticity" => "error"}, %{"code" => "b", "criticity" => "warning"}]
      iex> df = to_dataframe(errors)
      iex> digest(df) |> Map.keys() |> Enum.sort()
      ["max_severity", "stats", "summary"]
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
    %{"category" => categorize(mandatory_attributes["code"])}
  end

  defp categorize(code) do
    if String.starts_with?(code, "xsd-") do
      Commons.xsd_schema_category()
    else
      Commons.base_rules_category()
    end
  end

  @doc """
  Converts raw error list directly to a parquet binary — no intermediate grouping.

  ## Examples

      iex> errors = [%{"code" => "xsd-1", "criticity" => "error"}]
      iex> binary = to_binary_result(errors)
      iex> is_binary(binary)
      true
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def to_binary_result(errors) do
    errors
    |> to_dataframe()
    |> Commons.to_binary()
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summarize_xsd_errors(_binary_result), do: []
end
