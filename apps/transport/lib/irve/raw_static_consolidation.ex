defmodule Transport.IRVE.RawStaticConsolidation do
  import Transport.IRVE.Static.Probes

  @moduledoc """
  To be deleted.
  """

  require Explorer.DataFrame

  # needed to filter out the existing, data-gouv provided consolidation
  @datagouv_organization_id Application.compile_env!(:transport, :datagouvfr_publisher_id)
  # Filter also our own consolidation!
  @transport_organization_id Application.compile_env!(:transport, :datagouvfr_transport_publisher_id)
  # similarly, required to eliminate a test file
  @test_dataset_id "67811b8e8934d388950bca3f"

  @doc """
  Ensure that binary content is valid UTF-8. If not, attempt conversion from
  Latin-1 to UTF-8, assuming the original encoding is Latin-1.

  NOTE: This is not foolproof. The function does not verify that the input is
  actually Latin-1. Any byte sequence is technically valid Latin-1. However,
  based on our typical data sources (primarily French), this assumption allows
  us to recover and correctly convert over 100 additional resources.

  Example: already valid UTF-8 is returned unchanged.

      iex> Transport.IRVE.RawStaticConsolidation.ensure_utf8("valid utf8")
      "valid utf8"

  The byte `0xE9` represents "é" in Latin-1. The function converts it accordingly:

      iex> Transport.IRVE.RawStaticConsolidation.ensure_utf8(<<0xE9>>)
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

  def run_cheap_blocking_checks(body, extension) do
    if Transport.ZipProbe.likely_zip_content?(body) do
      raise("the content is likely to be a zip file, not uncompressed CSV data")
    end

    if String.downcase(extension) not in ["", ".csv"] do
      raise("the content is likely not a CSV file (extension is #{extension})")
    end

    if probably_v1_schema(body) do
      raise("looks like a v1 irve")
    end

    if !has_id_pdc_itinerance(body) do
      raise("content has no id_pdc_itinerance in first line")
    end

    header_separator = hint_header_separator(body)

    unless header_separator in [";", ","] do
      raise("unsupported column separator #{header_separator}")
    end
  end

  def ensure_producer_is_org!(%{dataset_organisation_id: "???"}), do: raise("producer is not an organization")

  def ensure_producer_is_org!(_row), do: :ok

  def exclude_irrelevant_resources(stream) do
    stream
    # exclude data gouv generated consolidation
    |> Enum.reject(fn r -> r.dataset_organisation_id == @datagouv_organization_id end)
    # also exclude "test dataset" https://www.data.gouv.fr/en/datasets/test-data-set
    # which is a large file marked as IRVE
    |> Enum.reject(fn r -> r.dataset_id == @test_dataset_id end)
    |> Enum.reject(fn r -> r.dataset_organisation_id == @transport_organization_id end)
  end
end
