defmodule Transport.IRVE.V3.Reader do
  @moduledoc """
  File-level checks of an IRVE v3 CSV, then loading as an all-strings data frame.

  Strict by design, as no v3 data exists yet (unlike the v2, which fixes encoding and delimiter silently):
  the file must be UTF-8, comma-delimited, with exactly the schema columns in schema order.
  """

  @doc """
  Gives `{:ok, data frame}` or `{:error, file-level errors}`, each error being a map with a `code`.
  """
  def read(body, field_names) when is_binary(body) do
    with :ok <- check_encoding(body),
         {:ok, df} <- load(body),
         :ok <- check_header(Explorer.DataFrame.names(df), field_names) do
      {:ok, df}
    end
  end

  defp check_encoding(body) do
    if String.valid?(body), do: :ok, else: {:error, [%{code: "encoding"}]}
  end

  defp load(body) do
    case Explorer.DataFrame.load_csv(body, infer_schema_length: 0, delimiter: ",") do
      {:ok, df} -> {:ok, df}
      {:error, error} -> {:error, [%{code: "csv", message: Exception.message(error)}]}
    end
  end

  # A wrong delimiter shows up here, as a single unexpected column.
  defp check_header(names, names), do: :ok

  defp check_header(names, field_names) do
    case {field_names -- names, names -- field_names} do
      {[], []} -> {:error, [%{code: "header_order"}]}
      {missing, unexpected} -> {:error, [%{code: "header", missing: missing, unexpected: unexpected}]}
    end
  end
end
