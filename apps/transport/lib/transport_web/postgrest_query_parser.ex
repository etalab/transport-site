defmodule PostgrestQueryParser do
  import NimbleParsec

  @moduledoc """
  Implement a subset of Postgrest params parsing. See:

  https://postgrest.org/en/latest/references/api/tables_views.html#operators

  Postgrest implements a way to express filtering via URL parameters,
  which is used in a large amount of cases. Instead of reinventing the wheel
  for our own filtering, this module leverages the grammar spec and reimplements
  a tiny part of it, while allowing future extensions with an already defined spec.
  """

  defcombinatorp(
    :value,
    ascii_string([?a..?z, ?A..?Z, ?0..?9], min: 1)
  )

  defcombinatorp(
    :values_array,
    ignore(ascii_char([?(]))
    |> concat(repeat(parsec(:value) |> ignore(optional(ignore(ascii_char([?,]))))))
    |> ignore(ascii_char([?)]))
    |> reduce({Enum, :into, [[]]})
  )

  in_op = string("in") |> ignore(string(".")) |> concat(parsec(:values_array))
  eq_op = string("eq") |> ignore(string(".")) |> parsec(:value)

  defparsecp(:do_parse, choice([in_op, eq_op]))

  @doc """
  iex> PostgrestQueryParser.parse("eq.AB123")
  {:ok, [:eq, "AB123"]}

  iex> PostgrestQueryParser.parse("in.(AB123,CD456)")
  {:ok, [:in, ["AB123", "CD456"]]}

  iex> {:error, _} = PostgrestQueryParser.parse("foo.(AB123,CD456)")
  """
  def parse(expr) do
    case do_parse(expr) do
      {:ok, [op, values], "" = _rest, _context, _line, _offset} ->
        {:ok, [op |> String.to_atom(), values]}

      {:error, reason, _rest, _context, _line, _offset} ->
        {:error, reason}
    end
  end
end
