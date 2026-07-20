defmodule Mix.Tasks.CheckLinks do
  @shortdoc "Check all HTTP/HTTPS links in git-tracked markdown files"
  @moduledoc """
  Validates every HTTP/HTTPS URL found in markdown files tracked by git.

  ## Usage

      mix check_links

  ## Environment variables

  - `LINK_CHECK_TIMEOUT` — per-request timeout in seconds (default: `10`)
  - `LINK_CHECK_RETRIES` — retry count on non-2xx/3xx (default: `2`)
  - `LINK_CHECK_SKIP_HOSTS` — comma-separated list of hosts to skip entirely

  Known-faulty markdown files are skipped by default (see `@skip_files`).
  """

  @skip_files [
    "docs/inventaire_donnees_geographiques_septembre_2023.md"
  ]

  use Mix.Task
  require Logger

  def run(_argv) do
    Application.ensure_started(:telemetry)

    timeout = System.get_env("LINK_CHECK_TIMEOUT", "10") |> String.to_integer()
    retries = System.get_env("LINK_CHECK_RETRIES", "2") |> String.to_integer()

    {:ok, _pid} = Finch.start_link(name: CheckLinks.Finch)

    markdown_files = git_markdown_files() |> skip_files()
    Logger.info("Checking links in #{length(markdown_files)} markdown file(s)")

    urls_with_files = extract_all_urls(markdown_files) |> deduplicate_urls()

    results =
      urls_with_files
      |> Enum.map(fn {url, file} ->
        Task.async(fn -> check_url(file, url, timeout, retries) end)
      end)
      |> await_many()

    ok_count = Enum.count(results, fn {_file, _url, status} -> status == :ok end)
    error_count = length(urls_with_files) - ok_count
    errors = Enum.filter(results, fn {_file, _url, status} -> is_integer(status) end)

    Logger.info("#{ok_count} ok, #{error_count} broken link(s)")

    if error_count > 0 do
      errors
      |> Enum.sort_by(fn {_file, url, _status} -> url end)
      |> Enum.each(fn {file, url, status} ->
        Logger.error("ERROR #{file}: #{url} (HTTP #{status})")
      end)

      System.stop(1)
    else
      Logger.info("All links are valid")
    end
  end

  defp await_many(tasks, timeout \\ 30_000),
    do: Enum.map(tasks, &Task.await(&1, timeout))

  # ---- git file discovery ---------------------------------------------------

  defp git_markdown_files do
    {stdout, _exit_code} = System.cmd("git", ["ls-files", "--", "*.md", "*.MD"])
    String.split(stdout, "\n", trim: true)
  end

  defp skip_files(files) do
    skipped = Enum.filter(files, &(&1 in @skip_files))

    if Enum.empty?(skipped) do
      files
    else
      filtered = Enum.reject(files, &(&1 in @skip_files))
      Logger.info("Skipping #{length(skipped)} file(s): #{Enum.join(skipped, ", ")}")
      filtered
    end
  end

  # ---- URL extraction --------------------------------------------------------

  defp extract_all_urls(files) do
    files
    |> Enum.flat_map(fn file ->
      content = File.read!(file)

      urls =
        Regex.scan(~r/\[([^\]]*)\]\((https?:\/\/[^)]+)\)/, content) ++
          Regex.scan(~r/<(https?:\/\/[^>]+)>/, content) ++
          Regex.scan(~r/^\s*\[([^\]]+)\]:\s+(https?:\/\/.+)$/m, content)

      urls
      |> Enum.map(fn [_full | rest] -> List.last(rest) end)
      |> Enum.map(&strip_trailing_punctuation/1)
      |> Enum.reject(&localhost?/1)
      |> Enum.reject(&private_repository?/1)
      |> Enum.reject(&skipped_host?/1)
      |> Enum.map(&{&1, file})
    end)
  end

  defp deduplicate_urls(urls_with_files) do
    urls_with_files |> Enum.uniq_by(fn {url, _file} -> url end)
  end

  # ---- URL parsing helpers ---------------------------------------------------

  defp strip_trailing_punctuation(url),
    do: Regex.replace(~r/[.,;!)>?]$/, url, "")

  defp localhost?(url), do: url =~ ~r/^https?:\/\/(127\.|localhost)/

  defp private_repository?(url), do: String.starts_with?(url, "https://github.com/transportdatagouvfr/proxy-config")

  defp skipped_host?(url) do
    host = parse_host(url)
    hosts = System.get_env("LINK_CHECK_SKIP_HOSTS", "") |> String.split(",", trim: true)
    Enum.any?(hosts, &(&1 == host))
  end

  defp parse_host(url),
    do: url |> URI.parse() |> Map.get(:host, "")

  # ---- HTTP check ------------------------------------------------------------

  defp check_url(file, url, timeout, retries), do: {file, url, do_check(url, timeout, retries)}

  defp do_check(_url, _timeout, 0), do: 0

  defp do_check(url, timeout, remaining_retries) do
    request = Finch.build(:head, url)

    case Finch.request(request, CheckLinks.Finch, recv_timeout: timeout * 1000) do
      {:ok, %{status: status}} when status in 200..399 -> :ok
      {:ok, %{status: 405}} -> get_fallback(url, timeout, remaining_retries - 1)
      {:ok, %{status: _status}} -> do_check(url, timeout, remaining_retries - 1)
      {:error, _reason} -> do_check(url, timeout, remaining_retries - 1)
    end
  end

  defp get_fallback(_url, _timeout, 0), do: 0

  defp get_fallback(url, timeout, remaining_retries) do
    request = Finch.build(:get, url)

    case Finch.request(request, CheckLinks.Finch, recv_timeout: timeout * 1000) do
      {:ok, %{status: status}} when status in 200..399 -> :ok
      {:ok, %{status: _status}} -> get_fallback(url, timeout, remaining_retries - 1)
      {:error, _reason} -> get_fallback(url, timeout, remaining_retries - 1)
    end
  end
end
