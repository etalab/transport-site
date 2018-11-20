defmodule Transport.Partners.Partner do
  @moduledoc """
  Partner model
  """
  use Vex.Struct

  @pool DBConnection.Poolboy

  defstruct url: nil

  defmodule Validations do
    @moduledoc """
    Validations of partner
    """
    @datagouv_url Application.get_env(:transport, :datagouvfr_site)
    @regex Regex.compile!(Regex.escape(@datagouv_url) <> ".*\/organizations|users\/.*")
    def is_datagouv_partner?(url), do: Regex.run(@regex, url)
  end

  validates :url, [
    presence: true,
    by: &Validations.is_datagouv_partner?/1
  ]

  def insert(%__MODULE__{} = partner) do
    Mongo.insert_one(:mongo, "partners", partner, pool: @pool)
  end

  def list do
    :mongo
    |> Mongo.find("partners", %{}, pool: @pool)
    |> Enum.map(&(%__MODULE__{url: &1["url"]}))
  end
end
