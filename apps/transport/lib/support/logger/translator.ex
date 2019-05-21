defmodule Support.Logger.Translator do
  @moduledoc """
  Filters but supervisor and children crashes from Erlang log messages.
  """

  def translate(_min_level, :error, :format, _message) do
    :none
  end

  def translate(_min_level, :error, :report, {:supervisor_report, _data}) do
    :none
  end

  def translate(_min_level, _level, _kind, _message) do
    :skip
  end
end
