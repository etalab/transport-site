defmodule Transport.Validation do
  @moduledoc """
  Validation model
  """
  use Ecto.Schema
  alias Transport.Resource
  import TransportWeb.Gettext, only: [dgettext: 2]

  schema "validations" do
    field :details, :map
    field :date, :string

    belongs_to :resource, Resource
  end

  def severities, do: %{
    "Fatal" => %{level: 0, text: dgettext("validations", "Fatal failures")},
    "Error" => %{level: 1, text: dgettext("validations", "Errors")},
    "Warning" => %{level: 2, text: dgettext("validations", "Warnings")},
    "Information" => %{level: 3, text: dgettext("validations", "Informations")},
    "Irrelevant" => %{level: 4, text: dgettext("validations", "Passed validations")},
    }

  def severities(key), do: severities()[key]
end
