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

  @doc """
  Returns the maximum severity, with the issues count

  iex> validation_result = %{"uic-operating-period" => [%{"criticity" => "error"}], "valid-day-bits" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  %{"max_level" => "error", "worst_occurrences" => 2}
  iex> validation_result = %{"frame-arret-resources" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  %{"max_level" => "warning", "worst_occurrences" => 1}
  iex> count_max_severity(%{})
  %{"max_level" => "NoError", "worst_occurrences" => 0}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_max_severity(validation_result) when validation_result == %{} do
    %{"max_level" => @no_error, "worst_occurrences" => 0}
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_max_severity(%{} = validation_result) do
    {max_level, worst_occurrences} =
      validation_result
      |> count_by_severity()
      |> Enum.min_by(fn {severity, _count} -> severity |> severity_level() end)

    %{"max_level" => max_level, "worst_occurrences" => worst_occurrences}
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def no_error?(severity), do: @no_error == severity

  @spec severity_level(binary()) :: integer()
  def severity_level(key) do
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
  iex> validation_result = %{"uic-operating-period" => [%{"code" => "uic-operating-period", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "valid-day-bits" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}], "frame-arret-resources" => [%{"code" => "frame-arret-resources", "message" => "Tag frame_id doesn't match ''", "criticity" => "warning"}]}
  iex> summary(validation_result)
  [
    %{"severity" => "error", "issues" => [
      %{"key" => "uic-operating-period", "issue" => %{"count" => 1, "criticity" => "error", "title" => "UIC operating period"}},
      %{"key" => "valid-day-bits", "issue" => %{"count" => 1, "criticity" => "error", "title" => "Valid day bits"}}
    ]},
    %{"severity" => "warning", "issues" => [%{"key" => "frame-arret-resources", "issue" => %{"count" => 1, "criticity" => "warning", "title" => "Frame arret resources"}}]}
  ]
  iex> summary(%{})
  []
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summary(%{} = validation_result) do
    validation_result
    |> Enum.map(fn {code, errors} ->
      {code,
       %{
         "count" => length(errors),
         "criticity" => errors |> hd() |> Map.get("criticity"),
         "title" => issues_short_translation_per_code(code)
       }}
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
        |> order_issues_by_location()
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

  def order_issues_by_location(%Explorer.DataFrame{} = df) do
    df
    |> DF.sort_by(&[&1["resource.filename"], &1["resource.line"], &1["message"]])
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def french_profile_compliance_check, do: :none

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def digest(validation_result) do
    %{
      "summary" => summary(validation_result),
      "stats" => count_by_severity(validation_result),
      "max_severity" => count_max_severity(validation_result)
    }
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def to_dataframe(errors), do: Commons.to_dataframe(errors, fn _ -> %{} end)

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def to_binary_result(result) do
    result
    |> Map.values()
    |> List.flatten()
    |> to_dataframe()
    |> Commons.to_binary()
  end

  @impl Transport.Validators.NeTEx.ResultsAdapter
  def summarize_xsd_errors(_binary_result), do: []
end
