defmodule Transport.Cldr do
  @moduledoc """
  Declares a backend for Cldr as required.
  https://hexdocs.pm/ex_cldr_numbers/readme.html#introduction-and-getting-started
  """
  use Cldr, locales: ["en", "fr"], providers: [Cldr.Number, Cldr.Calendar, Cldr.Unit, Cldr.List], default_locale: "fr"
end
