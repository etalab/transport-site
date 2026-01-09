defmodule Transport.TmpFile do
  @moduledoc """
  Reusable abstraction to create & delete temporary files during tests.
  """

  @doc """
  Create a tmp file with the provided content, run the provided `cb` method
  and pass it the tmp file path. Ensure the file is deleted afterward.
  """
  def with_tmp_file(content, cb) do
    tmp_path = System.tmp_dir!() |> Path.join("transport_test_file_#{Ecto.UUID.generate()}.dat")

    try do
      File.write!(tmp_path, content)
      cb.(tmp_path)
    after
      File.rm(tmp_path)
    end
  end
end
