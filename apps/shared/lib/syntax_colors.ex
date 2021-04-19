defmodule Transport.Inspect do
  @moduledoc """
  While creating scripts (`mix run script.exs`), it is useful to
  color-pretty-print data structures, like `IEx` does.

  This module provides tooling for this.
  """

  # Taken from https://github.com/elixir-lang/elixir/blob/7ec5cc63e67de75816ae018766331fcf9c55faa8/lib/iex/lib/iex/config.ex#L107
  # which does not publicly expose this currently.
  @syntax_colors [
    atom: :cyan,
    string: :green,
    number: :yellow,
    list: :default_color,
    boolean: :magenta,
    nil: :magenta,
    tuple: :default_color,
    binary: :default_color,
    map: :default_color
  ]

  @doc """
  Expose syntax color for use with `IO.inspect`'s `syntax_colors` option
  """
  def syntax_colors, do: @syntax_colors

  @doc """
  Shortcut to color-pretty-print something easily
  """
  def pretty_inspect(data) do
    IO.inspect(data, syntax_colors: syntax_colors())
  end
end
