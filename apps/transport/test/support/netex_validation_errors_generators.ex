defmodule NetexValidationErrorsGenerators do
  @moduledoc """
  Generators for NeTEx validation error maps, used in property-based tests.
  """

  import StreamData

  @doc false
  def criticity do
    one_of([constant("error"), constant("warning"), constant("information"), constant("unexpected")])
  end

  @doc false
  def filename do
    list_of(string(:alphanumeric, length: 1..10), length: 1..3)
    |> map(fn segments ->
      base = List.last(segments) <> ".xml"
      dirs = Enum.drop(segments, -1)

      case dirs do
        [] -> base
        _ -> Enum.join(dirs ++ [base], "/")
      end
    end)
  end

  @doc false
  def line_number do
    integer(0..4_294_967_295)
  end

  @doc false
  def message do
    string(:alphanumeric, length: 3..30)
  end

  @doc false
  def code do
    bind(integer(0..999), fn n ->
      constant("rule_#{String.pad_leading(to_string(n), 3, "0")}")
    end)
  end

  @doc false
  def single_error do
    bind({code(), criticity(), message(), filename(), line_number()}, fn {
                                                                           code,
                                                                           criticity,
                                                                           message,
                                                                           filename,
                                                                           line
                                                                         } ->
      constant(%{
        "code" => code,
        "criticity" => criticity,
        "message" => message,
        "resource" => %{"filename" => filename, "line" => line}
      })
    end)
  end

  @doc false
  def error_list(n) when is_integer(n) and n >= 0 do
    list_of(single_error(), length: n)
  end
end
