defmodule Transport.ReusableData.Licence do
  @moduledoc """
  Representation of different licences, localised.
  """

  import TransportWeb.Gettext

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{
    name: String.t
  }

  @doc """
  Initialises a licence struct with a given code. If the code is within a known
  list of codes, it is localised to the current Gettext locale.

  ## Examples

      iex> Licence.new("fr-lo")
      %Licence{name: "Licence ouverte"}

      iex> Licence.new("asdf")
      %Licence{name: "asdf"}

  """
  @spec new(String.t) :: %__MODULE__{}
  def new(code) do
    case code do
      "fr-lo" -> %__MODULE__{name: dgettext("reusable_data", "fr-lo")}
      "odc-odbl" -> %__MODULE__{name: dgettext("reusable_data", "odc-odbl")}
      "other-open" -> %__MODULE__{name: dgettext("reusable_data", "other-open")}
      "notspecified" -> %__MODULE__{name: dgettext("reusable_data", "notspecified")}
      other -> %__MODULE__{name: other}
    end
  end
end
