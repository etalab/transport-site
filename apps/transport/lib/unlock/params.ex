defmodule Unlock.Params do
  @moduledoc false

  def to_boolean(nil), do: false
  def to_boolean("0"), do: false
  def to_boolean("1"), do: true

  def to_nil_or_integer(nil), do: nil
  def to_nil_or_integer(s), do: String.to_integer(s)
end
