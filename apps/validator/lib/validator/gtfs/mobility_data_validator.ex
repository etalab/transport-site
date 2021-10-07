defmodule Validator.Gtfs.MobilityDataValidator do
  @moduledoc """
  Execute gtfs validator with the following command:

  `$ java -jar gtfs-validator.jar -o output -i ./<gtfs_zip_path> -c FR`
  """

  defmodule MobilityDataValidator.Config do
    def fetch(key) when is_atom(key), do: Application.fetch_env!(:validation, :mobility_data)[key]
  end

  alias MobilityDataValidator.Config

  @report_filename "report.json"
  @system_errors_filename "system_errors.json"

  @enforce_keys [:gtfs_path, :output_dir]
  defstruct [
    :gtfs_path,
    :output_dir,
    :exit_code,
    :output_logs,
    :system_errors,
    :report,
    :status,
    :severity
  ]

  @doc """
  Create a new validation ready to be executed
  """
  def new(gtfs_path) do
    output_dir =
      gtfs_path
      |> Path.basename()
      |> resolve_output_dir

    %__MODULE__{gtfs_path: gtfs_path, output_dir: output_dir}
  end

  @doc """
  Execute a given validation
  """
  def execute(%__MODULE__{} = validation), do: validation |> execute_gtfs_validator()

  @doc """
  Parse output for a given validation such as exit code and generated files
  """
  def parse_outputs(%__MODULE__{} = validation),
    do:
      validation
      |> read_file_into(@report_filename, :report)
      |> read_file_into(@system_errors_filename, :system_errors)
      |> update_validation_status()

  defp resolve_output_dir(gtfs_filename), do: Path.join(working_directory(), gtfs_filename)

  # TODO use Rambo to execute command instead of System.cmd/2
  defp execute_gtfs_validator(
         %__MODULE__{gtfs_path: gtfs_path, output_dir: output_dir} = validation
       ) do
    {command_output, exit_code} =
      System.cmd(
        "java",
        ["-jar", gtfs_validator_bin(), "-o", output_dir, "-i", gtfs_path, "-f", "fr-test"],
        into: [],
        stderr_to_stdout: true
      )

    %__MODULE__{validation | exit_code: exit_code, output_logs: command_output}
  end

  defp gtfs_validator_bin, do: Config.fetch(:bin)

  defp read_file_into(%__MODULE__{output_dir: output_dir} = validation, filename, into) do
    report_file_path = "#{output_dir}/#{filename}"

    output =
      case File.exists?(report_file_path) do
        true ->
          report_file_path
          |> File.read!()
          |> Jason.decode!()

        false ->
          nil
      end

    Map.put(validation, into, output)
  end

  defp update_validation_status(%__MODULE__{exit_code: 1} = validation),
    do: Map.put(validation, :status, :failed)

  defp update_validation_status(%__MODULE__{system_errors: %{"notices" => notices}} = validation)
       when length(notices) > 0,
       do: Map.put(validation, :status, :failed)

  defp update_validation_status(%__MODULE__{report: %{"notices" => notices}} = validation)
       when length(notices) > 0 do
    severities =
      notices
      |> Enum.map(&Map.fetch!(&1, "severity"))

    severity =
      cond do
        "ERROR" in severities -> :error
        "WARNING" in severities -> :warning
        "INFO" in severities -> :info
        true -> :unknown
      end

    validation
    |> Map.put(:status, :notices)
    |> Map.put(:severity, severity)
  end

  defp update_validation_status(validation), do: Map.put(validation, :status, :succeed)

  defp working_directory, do: Config.fetch(:working_directory)
end
