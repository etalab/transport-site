defmodule DB.Repo.Migrations.Unaccent do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION unaccent")

    execute(
      """
      ALTER TEXT SEARCH CONFIGURATION simple
      ALTER MAPPING FOR hword, hword_part, hword_asciipart, word
      WITH unaccent, simple;
      """,
      """
      ALTER TEXT SEARCH CONFIGURATION simple
      ALTER MAPPING FOR hword, hword_part, hword_asciipart, word
      WITH simple;
      """
    )
  end
end
