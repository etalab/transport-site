defmodule Transport.Cldr do
  use Cldr, locales: ["en", "fr"], providers: [Cldr.Number], default_locale: "fr"
end
