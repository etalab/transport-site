defmodule Transport.ReusableData.Licence do
  @moduledoc """
  Representation of different licences, localised.
  """

  import TransportWeb.Gettext
  alias Transport.ReusableData.Licence

  defstruct [:name]

  def new(code) do
    case code do
      "fr-lo" -> %Licence{name: dgettext("reusable_data", "fr-lo")}
      "odc-odbl" -> %Licence{name: dgettext("reusable_data", "odc-odbl")}
      "other-open" -> %Licence{name: dgettext("reusable_data", "other-open")}
      "notspecified" -> %Licence{name: dgettext("reusable_data", "notspecified")}
      other -> %Licence{name: other}
    end
  end
end
