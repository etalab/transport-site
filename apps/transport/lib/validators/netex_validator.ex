defmodule Transport.Validators.NeTEx do
  @moduledoc """
  Validator for NeTEx files calling enRoute Chouette Valid API. This is blocking
  (by polling the tier API) and can take quite some time upon completion.
  """

  import TransportWeb.Gettext, only: [dgettext: 2]
  require Logger

  @no_error "NoError"

  @max_retries 100

  @unknown_code "unknown-code"

  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validator_name, do: "enroute-chouette-netex-validator"

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.Resource{format: "NeTEx", id: resource_id}) do
    Logger.info("Validating NeTEx #{resource_id} with enRoute Chouette Valid")

    resource_history = DB.ResourceHistory.latest_resource_history(resource_id)
    with_resource_file(resource_history, &validate_resource_history(resource_history, &1))
  end

  def validate_resource_history(resource_history, filepath) do
    case validate_with_enroute(filepath) do
      {:ok, %{url: result_url, elapsed_seconds: elapsed_seconds, retries: retries}} ->
        insert_validation_results(resource_history.id, result_url, %{elapsed_seconds: elapsed_seconds, retries: retries})

        :ok

      {:error, %{details: {result_url, errors}, elapsed_seconds: elapsed_seconds, retries: retries}} ->
        insert_validation_results(
          resource_history.id,
          result_url,
          %{elapsed_seconds: elapsed_seconds, retries: retries},
          demote_non_xsd_errors(errors)
        )

        :ok

      {:error, :unexpected_validation_status} ->
        Logger.error("Invalid API call to enRoute Chouette Valid")
        {:error, "enRoute Chouette Valid: Unexpected validation status"}

      {:error, %{message: :timeout, retries: _retries}} ->
        Logger.error("Timeout while fetching result on enRoute Chouette Valid")
        {:error, "enRoute Chouette Valid: Timeout while fetching results"}
    end
  end

  @type validate_options :: [{:graceful_retry, boolean()}]

  @doc """
  Validate the resource from the given URL.

  Options can be passed to tweak the behaviour:
  - graceful_retry is a flag to skip the polling interval. Useful for testing
    purposes mostly. Defaults to false.
  """
  @spec validate(binary(), validate_options()) :: {:ok, map()} | {:error, binary()}
  def validate(url, opts \\ []) do
    with_url(url, fn filepath ->
      case validate_with_enroute(filepath, opts) do
        {:ok, %{url: result_url, elapsed_seconds: elapsed_seconds, retries: retries}} ->
          # result_url in metadata?
          Logger.info("Result URL: #{result_url}")

          {:ok,
           %{"validations" => index_messages([]), "metadata" => %{elapsed_seconds: elapsed_seconds, retries: retries}}}

        {:error, %{details: {result_url, errors}, elapsed_seconds: elapsed_seconds, retries: retries}} ->
          Logger.info("Result URL: #{result_url}")
          # result_url in metadata?
          {:ok,
           %{
             "validations" => errors |> demote_non_xsd_errors() |> index_messages(),
             "metadata" => %{elapsed_seconds: elapsed_seconds, retries: retries}
           }}

        {:error, :unexpected_validation_status} ->
          Logger.error("Invalid API call to enRoute Chouette Valid")
          {:error, %{message: "enRoute Chouette Valid: Unexpected validation status"}}

        {:error, %{message: :timeout, retries: retries}} ->
          Logger.error("Timeout while fetching result on enRoute Chouette Valid")
          {:error, %{message: "enRoute Chouette Valid: Timeout while fetching results", retries: retries}}
      end
    end)
  end

  @spec with_resource_file(DB.ResourceHistory.t(), (Path.t() -> any())) :: any()
  def with_resource_file(resource_history, closure) do
    %DB.ResourceHistory{payload: %{"permanent_url" => permanent_url}} = resource_history
    filepath = tmp_path(resource_history)

    with_tmp_file(permanent_url, filepath, closure)
  end

  @spec with_url(binary(), (Path.t() -> any())) :: any()
  def with_url(url, closure) do
    with_tmp_file(url, tmp_path(url), closure)
  end

  @spec with_tmp_file(binary(), Path.t(), (Path.t() -> any())) :: any()
  def with_tmp_file(url, filepath, closure) do
    http_client().get!(url, compressed: false, into: File.stream!(filepath))
    closure.(filepath)
  after
    File.rm(filepath)
  end

  defp http_client, do: Transport.Req.impl()

  defp tmp_path(%DB.ResourceHistory{id: resource_history_id}) do
    System.tmp_dir!() |> Path.join("enroute_validation_netex_#{resource_history_id}")
  end

  defp tmp_path(_other) do
    System.tmp_dir!() |> Path.join("enroute_validation_netex_#{Ecto.UUID.generate()}")
  end

  def insert_validation_results(resource_history_id, result_url, metadata, errors \\ []) do
    result = index_messages(errors)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: result,
      resource_history_id: resource_history_id,
      validator_version: validator_version(),
      command: result_url,
      max_error: get_max_severity_error(result),
      metadata: %DB.ResourceMetadata{metadata: metadata}
    }
    |> DB.Repo.insert!()
  end

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
  @spec count_max_severity(map()) :: {binary(), integer()}
  def count_max_severity(validation_result) when validation_result == %{} do
    {@no_error, 0}
  end

  def count_max_severity(%{} = validation_result) do
    validation_result
    |> count_by_severity()
    |> Enum.min_by(fn {severity, _count} -> severity |> severity() |> Map.get(:level) end)
  end

  @spec severities_map() :: map()
  def severities_map,
    do: %{
      "error" => %{level: 1, text: dgettext("netex-validator", "errors")},
      "warning" => %{level: 2, text: dgettext("netex-validator", "warnings")},
      "information" => %{level: 3, text: dgettext("netex-validator", "informations")}
    }

  @spec severity(binary()) :: %{level: integer(), text: binary()}
  def severity(key), do: severities_map()[key]

  @doc """
  Returns the number of issues by severity level

  iex> validation_result = %{"uic-operating-period" => [%{"criticity" => "warning"}], "valid-day-bits" => [%{"criticity" => "error"}], "frame-arret-resources" => [%{"criticity" => "error"}]}
  iex> count_by_severity(validation_result)
  %{"warning" => 1, "error" => 2}

  iex> count_by_severity(%{})
  %{}
  """
  @spec count_by_severity(map()) :: map()
  def count_by_severity(%{} = validation_result) do
    validation_result
    |> Enum.flat_map(fn {_, v} -> v end)
    |> Enum.reduce(%{}, fn v, acc -> Map.update(acc, v["criticity"], 1, &(&1 + 1)) end)
  end

  def count_by_severity(_), do: %{}

  defp validate_with_enroute(filepath, opts \\ []) do
    client().create_a_validation(filepath) |> fetch_validation_results(0, opts)
  end

  defp fetch_validation_results(validation_id, retries, opts) do
    case client().get_a_validation(validation_id) do
      :pending when retries >= @max_retries ->
        {:error, %{message: :timeout, retries: retries}}

      :pending ->
        if Keyword.get(opts, :graceful_retry, true) do
          retries |> poll_interval() |> :timer.sleep()
        end

        fetch_validation_results(validation_id, retries + 1, opts)

      {:successful, url, elapsed_seconds} ->
        {:ok, %{url: url, elapsed_seconds: elapsed_seconds, retries: retries}}

      {value, elapsed_seconds} when value in [:warning, :failed] ->
        {:error, %{details: client().get_messages(validation_id), elapsed_seconds: elapsed_seconds, retries: retries}}

      :unexpected_validation_status ->
        {:error, :unexpected_validation_status}
    end
  end

  @doc """
  Poll interval to play nice with the tier.

  iex> 0..9 |> Enum.map(&poll_interval(&1))
  [10000, 10000, 10000, 10000, 10000, 10000, 20000, 20000, 20000, 20000]
  """
  def poll_interval(nb_tries) when nb_tries < 6, do: 10_000
  def poll_interval(_), do: 20_000

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

  # This will change with an actual versioning of the validator
  def validator_version, do: "saas-production"

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
  @spec summary(map()) :: list()
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
    |> Enum.sort_by(fn {criticity, _} -> severity(criticity).level end)
  end

  @spec issues_short_translation_per_code(binary()) :: binary()
  def issues_short_translation_per_code(code) do
    if String.starts_with?(code, "xsd-") do
      dgettext("netex-validator", "XSD validation")
    else
      Map.get(issues_short_translation(), code, code)
    end
  end

  @spec issues_short_translation() :: %{binary() => binary()}
  def issues_short_translation,
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

  @spec issue_type(list()) :: nil | binary()
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
  def get_issues(%{} = validation_result, %{"issue_type" => issue_type}) do
    Map.get(validation_result, issue_type, []) |> order_issues_by_location()
  end

  def get_issues(%{} = validation_result, _) do
    validation_result
    |> Map.values()
    |> Enum.sort_by(fn [%{"criticity" => severity} | _] -> severity(severity).level end)
    |> List.first([])
    |> order_issues_by_location()
  end

  def get_issues(_, _), do: []

  def order_issues_by_location(issues) do
    issues
    |> Enum.sort_by(fn issue ->
      message = Map.get(issue, "message", "")
      resource = Map.get(issue, "resource", %{})
      filename = Map.get(resource, "filename", "")
      line = Map.get(resource, "line", "")
      {filename, line, message}
    end)
  end

  defp client do
    Transport.EnRouteChouetteValidClient.Wrapper.impl()
  end

  defp demote_non_xsd_errors(errors), do: Enum.map(errors, &demote_non_xsd_error(&1))

  defp demote_non_xsd_error(error) do
    code = Map.get(error, "code", "")

    if String.starts_with?(code, "xsd-") do
      error
    else
      Map.update!(error, "criticity", &demote_error/1)
    end
  end

  defp demote_error(criticity) do
    case criticity do
      "error" -> "warning"
      _ -> criticity
    end
  end
end
