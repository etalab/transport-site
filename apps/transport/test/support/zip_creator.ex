defmodule Transport.ZipCreator do
  @moduledoc """
  A light wrapper around OTP `:zip` features. Does not support streaming here,
  but massages the string <-> charlist differences.
  """
  def create!(zip_filename, file_data) do
    {:ok, ^zip_filename} =
      :zip.create(
        zip_filename,
        file_data
        |> Enum.map(fn {name, content} -> {name |> to_charlist(), content} end)
      )

    :ok
  end
end
