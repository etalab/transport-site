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

  If it is not, then it returns an error.

  ## Examples

      iex> Licence.new(%{name: "fr-lo"})
      %Licence{name: "Open Licence"}

      iex> Licence.new(%{name: "Lolbertarian"})
      %Licence{name: nil}

  """
  @spec new(map()) :: %__MODULE__{}
  def new(%{} = attrs) do
    case Map.get(attrs, :name) do
      "fr-lo" ->
        %__MODULE__{name: dgettext("reusable_data", "fr-lo")}
      "odc-odbl" ->
        %__MODULE__{name: dgettext("reusable_data", "odc-odbl")}
      "other-open" ->
        %__MODULE__{name: dgettext("reusable_data", "other-open")}
      "notspecified" ->
        %__MODULE__{name: dgettext("reusable_data", "notspecified")}
      _ ->
        %__MODULE__{name: nil}
    end
  end
end
