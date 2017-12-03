defmodule Transport.DataImprovement.Macros do
  @moduledoc """
  To be used as:

      use Transport.DataImprovement, :command
      use Transport.DataImprovement, :model
      use Transport.DataImprovement, :repository

  """

  def command do
    quote do
      use ExConstructor
      use Vex.Struct
      import TransportWeb.Gettext, only: [dgettext: 2] # smell
      defdelegate validate(struct), to: Vex
    end
  end

  def model do
    quote do
      use ExConstructor
    end
  end

  def repository do
    quote do
      # stuff
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
