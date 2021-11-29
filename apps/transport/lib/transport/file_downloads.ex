defmodule Transport.FileDownloads do
  @moduledoc """
  This module defines functions to help extract filenames
  from HTTP responses.
  """

  @doc ~S"""
  Guess a filename using HTTP response headers or an URL. The `content-disposition`
  HTTP header will be used in priority if available.

  ## Examples

    iex> Transport.FileDownloads.guess_filename(%{"content-disposition" => "attachment; filename=gtfs.zip"}, "https://example.com/foo.zip")
    "gtfs.zip"

    iex> Transport.FileDownloads.guess_filename(%{}, "https://example.com/foo.zip")
    "foo.zip"
  """
  def guess_filename(headers, url), do: extract_from_headers(headers) || extract_from_url(url)

  @doc ~S"""
  Extract a filename from a `content-disposition` HTTP header.

  ## Examples

    iex> Transport.FileDownloads.extract_from_headers(%{"content-disposition" => "attachment; filename=gtfs.zip"})
    "gtfs.zip"

    iex> Transport.FileDownloads.extract_from_headers([{"content-disposition", "attachment; filename=gtfs.zip"}])
    "gtfs.zip"

    iex> Transport.FileDownloads.extract_from_headers(%{"content-disposition" => "attachment; filename=\"gtfs.zip\""})
    "gtfs.zip"

    iex> Transport.FileDownloads.extract_from_headers(%{"content-disposition" => "attachment; filename=\"omáèka.jpg\""})
    "omáèka.jpg"

    iex> Transport.FileDownloads.extract_from_headers(%{"foo" => "bar"})
    nil
  """
  def extract_from_headers(headers) when is_map(headers) do
    with {_, content} <- Enum.find(headers, fn {h, _} -> String.downcase(h) == "content-disposition" end),
         %{"filename" => filename} <-
           Regex.named_captures(~r/filename[^;=\n]*=(?<filename>(['"]).*?\2|[^;\n]*)/, content) do
      String.replace(filename, ~s("), "")
    else
      _ -> nil
    end
  end

  def extract_from_headers(headers), do: headers |> Enum.into(%{}) |> extract_from_headers()

  @doc ~S"""
  Extract a filename from an URL.

  ## Examples

    iex> Transport.FileDownloads.extract_from_url("https://example.com/test_helper.exs#L1?ok=blah")
    "test_helper.exs"
  """
  def extract_from_url(url) when is_binary(url), do: url |> URI.parse() |> extract_from_url()

  def extract_from_url(%URI{path: path}) do
    path |> Path.basename()
  end
end
