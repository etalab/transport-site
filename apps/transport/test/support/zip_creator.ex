defmodule ZipCreator do
  @moduledoc """
  A light wrapper around OTP `:zip` features. Does not support streaming here,
  but massages the string <-> charlist differences.
  """
  @spec create!(String.t(), [{String.t(), binary()}]) :: no_return()
  def create!(zip_filename, file_data) do
    {:ok, ^zip_filename} =
      :zip.create(
        zip_filename,
        file_data
        |> Enum.map(fn {name, content} -> {name |> to_charlist(), content} end)
      )
  end

  def with_tmp_zip(entries, cb) do
    tmp_file = System.tmp_dir!() |> Path.join("temp-netex-#{Ecto.UUID.generate()}.zip")

    try do
      ZipCreator.create!(tmp_file, entries)
      cb.(tmp_file)
    after
      File.rm(tmp_file)
    end
  end
end
