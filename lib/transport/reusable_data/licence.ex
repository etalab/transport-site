defmodule Transport.ReusableData.Licence do
  @moduledoc """
  Representation of different licences, localised.
  """

  import TransportWeb.Gettext

  defstruct [:name]

  use ExConstructor

  @type t :: %__MODULE__{
    name: String.t
  }

  @localisations %{
    "fr-lo" => dgettext("reusable_data", "fr-lo"),
    "odc-odbl" => dgettext("reusable_data", "odc-odbl"),
    "other-open" => dgettext("reusable_data", "other-open"),
    "notspecified" => dgettext("reusable_data", "notspecified")
  }

  @doc """
  Initialises a licence struct with a given code. If the code is within a known
  list of codes, it is localised to the current Gettext locale.

  ## Examples

      iex> Licence.new(%{name: "fr-lo"})
      %Licence{name: "Open Licence"}

      iex> Licence.new(%{"name" => "fr-lo"})
      %Licence{name: "Open Licence"}

      iex> Licence.new(%{name: "Lolbertarian"})
      %Licence{name: nil}

      iex> Licence.new(%{})
      %Licence{name: nil}

  """
  @spec new(map()) :: %__MODULE__{}
  def new(%{} = attrs) do
    attrs
    |> super
    |> assign_localised_name
  end

  # private

  @spec assign_localised_name(%__MODULE__{}) :: %__MODULE__{}
  defp assign_localised_name(licence) do
    %__MODULE__{licence | name: Map.get(@localisations, licence.name)}
  end
end
