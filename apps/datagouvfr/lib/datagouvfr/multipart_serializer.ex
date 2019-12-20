defmodule Transport.Datagouvfr.MultipartSerializer do
  @moduledoc """
  Use to encode multipart/form-data body of requests
  """
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
