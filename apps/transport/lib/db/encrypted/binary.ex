defmodule DB.Encrypted.Binary do
  @moduledoc """
  An encrypted binary type suitable for `cloak_ecto`
  https://hexdocs.pm/cloak_ecto/install.html#create-local-ecto-types
  """
  use Cloak.Ecto.Binary, vault: Transport.Vault
end
