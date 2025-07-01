defmodule Transport.Validators.NeTEx.ResultsAdapters.V0_1_0 do
  @moduledoc """
  Helper module to build and interpret results for NeTEx validation prior to 0.2.0.
  """

  use Gettext, backend: TransportWeb.Gettext

  @behaviour Transport.Validators.NeTEx.ResultsAdapter

  @no_error "NoError"

  @unknown_code "unknown-code"

  @doc """
  Returns the maximum issue severity found

  iex> validation_result = %{"uic-operating-period" => [%{"criticity" => "error"}], "valid-day-bits" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "error"}]}
  iex> get_max_severity_error(validation_result)
  "error"

  iex> get_max_severity_error(%{})
  "NoError"
  """
  @spec get_max_severity_error(map()) :: binary() | nil
  def get_max_severity_error(validation_result) do
    {severity, _} = validation_result |> count_max_severity()
    severity
  end

  @doc """
  Returns the maximum severity, with the issues count

  iex> validation_result = %{"uic-operating-period" => [%{"criticity" => "error"}], "valid-day-bits" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  {"error", 2}
  iex> validation_result = %{"frame-arret-resources" => [%{"criticity" => "warning"}]}
  iex> count_max_severity(validation_result)
  {"warning", 1}
  iex> count_max_severity(%{})
  {"NoError", 0}
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def count_max_severity(validation_result) when validation_result == %{} do
    {@no_error, 0}
  end

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
  iex> Gettext.put_locale("fr")
  iex> format_severity("error", 1)
  "1 erreur"
  iex> format_severity("error", 2)
  "2 erreurs"
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def format_severity(key, count) do
    case key do
      "error" -> dngettext("netex-validator", "error", "errors", count)
      "warning" -> dngettext("netex-validator", "warning", "warnings", count)
      "information" -> dngettext("netex-validator", "information", "informations", count)
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

  iex> index_messages([%{"code"=>"a", "id"=> 1}, %{"code"=>"a", "id"=> 2}, %{"code"=>"b", "id"=> 3}])
  %{"a"=>[%{"code"=>"a", "id"=> 1}, %{"code"=>"a", "id"=> 2}], "b"=>[%{"code"=>"b", "id"=> 3}]}

  Sometimes the message has no code
  iex> index_messages([%{"code"=>"a", "id"=> 1}, %{"code"=>"b", "id"=> 2}, %{"id"=> 3}])
  %{"a"=>[%{"code"=>"a", "id"=> 1}], "b"=>[%{"code"=>"b", "id"=> 2}], "unknown-code"=>[%{"id"=> 3}]}
  """
  def index_messages(messages), do: Enum.group_by(messages, &get_code/1)

  defp get_code(%{"code" => code}), do: code
  defp get_code(%{}), do: @unknown_code

  @doc """
  iex> validation_result = %{"uic-operating-period" => [%{"code" => "uic-operating-period", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "valid-day-bits" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}], "frame-arret-resources" => [%{"code" => "frame-arret-resources", "message" => "Tag frame_id doesn't match ''", "criticity" => "warning"}]}
  iex> summary(validation_result)
  [
    {"error", [
      {"uic-operating-period", %{count: 1, criticity: "error", title: "UIC operating period"}},
      {"valid-day-bits", %{count: 1, criticity: "error", title: "Valid day bits"}}
    ]},
    {"warning", [{"frame-arret-resources", %{count: 1, criticity: "warning", title: "Frame arret resources"}}]}
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
         count: length(errors),
         criticity: errors |> hd() |> Map.get("criticity"),
         title: issues_short_translation_per_code(code)
       }}
    end)
    |> Enum.group_by(fn {_, details} -> details.criticity end)
    |> Enum.sort_by(fn {criticity, _} -> severity_level(criticity) end)
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

  iex> validation_result = %{"uic-operating-period" => [%{"code" => "uic-operating-period", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}], "valid-day-bits" => [%{"code" => "valid-day-bits", "message" => "Mandatory attribute valid_day_bits not found", "criticity" => "error"}], "frame-arret-resources" => [%{"code" => "frame-arret-resources", "message" => "Tag frame_id doesn't match ''", "criticity" => "warning"}]}
  iex> get_issues(validation_result, %{"issue_type" => "uic-operating-period"})
  [%{"code" => "uic-operating-period", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}]
  iex> get_issues(validation_result, %{"issue_type" => "broken-file"})
  []
  iex> get_issues(validation_result, nil)
  [%{"code" => "uic-operating-period", "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod", "criticity" => "error"}]
  iex> get_issues(%{}, nil)
  []
  iex> get_issues([], nil)
  []
  """
  @impl Transport.Validators.NeTEx.ResultsAdapter
  def get_issues(%{} = validation_result, %{"issue_type" => issue_type}) do
    Map.get(validation_result, issue_type, []) |> order_issues_by_location()
  end

  def get_issues(%{} = validation_result, _) do
    validation_result
    |> Map.values()
    |> Enum.sort_by(fn [%{"criticity" => severity} | _] -> severity_level(severity) end)
    |> List.first([])
    |> order_issues_by_location()
  end

  def get_issues(_, _), do: []

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
