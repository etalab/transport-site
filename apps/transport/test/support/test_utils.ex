defmodule Transport.Test.TestUtils do
  @moduledoc """
  Some useful functions for testing
  """

  def ensure_no_tmp_files!(file_prefix) do
    tmp_files = System.tmp_dir!() |> File.ls!()

    ExUnit.Assertions.assert(
      tmp_files |> Enum.filter(fn f -> String.starts_with?(f, file_prefix) end) |> Enum.empty?(),
      "tmp files found in #{System.tmp_dir!()}"
    )
  end
end
