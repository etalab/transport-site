defmodule Transport.IRVE.Transcoder do
  @moduledoc """
  This module allows a CSV encoded in latin-1 to be transcoded to UTF-8.
  It’s used both for validation and for database insertion.
  """

  @doc """
  Ensure that binary content is valid UTF-8. If not, attempt conversion from
  Latin-1 to UTF-8, assuming the original encoding is Latin-1.

  NOTE: This is not foolproof. The function does not verify that the input is
  actually Latin-1. Any byte sequence is technically valid Latin-1. However,
  based on our typical data sources (primarily French), this assumption allows
  us to recover and correctly convert over 100 additional resources.

  Example: already valid UTF-8 is returned unchanged.

      iex> Transport.IRVE.Transcoder.ensure_utf8("valid utf8")
      "valid utf8"

  The byte `0xE9` represents "é" in Latin-1. The function converts it accordingly:

      iex> Transport.IRVE.Transcoder.ensure_utf8(<<0xE9>>)
      "é"

  This function does not raise errors for any binary input. Only non-binary input
  (e.g., integers, maps) will raise an exception.
  """
  def ensure_utf8(body) do
    if String.valid?(body) do
      body
    else
      case :unicode.characters_to_binary(body, :latin1, :utf8) do
        converted when is_binary(converted) ->
          converted

        {:error, _, _} ->
          raise("error during latin 1 -> UTF-8 transcoding (should not happen)")

        {:incomplete, _, _} ->
          raise("string contains incomplete latin1 sequences")
      end
    end
  end
end
