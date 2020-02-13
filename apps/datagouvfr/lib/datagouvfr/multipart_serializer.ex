defmodule Transport.Datagouvfr.MultipartSerializer do
  @moduledoc """
  Use to encode multipart/form-data body of requests
  """
  @spec encode!({binary(), Plug.Upload.t()}) :: {:multipart, any()}
  def encode!({name, %Plug.Upload{} = file}) do
    {
      :multipart,
      [
        {
          :file,
          file.path,
          {
            "form-data",
            [
              {"name", "\"#{name}\""},
              {"filename", "\"#{file.filename}\""}
            ]
          },
          []
        }
      ]
    }
  end
end
