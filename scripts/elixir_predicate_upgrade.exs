file = "credo.json"

Mix.install([
  {:jason, "~> 1.4"}
])

# 4 means "readability" only
# See: https://github.com/rrrene/credo/blob/master/guides/introduction/exit_statuses.md#issue-statuses
{_, 4} = System.shell("mix credo --strict --format json > #{file}")

defmodule Patcher do
  import ExUnit.Assertions

  def build_new_method_name(old_method_name) do
    # we remove the heading "is_", but keep the trailing "?" (or add it if missing)
    new_method_name = String.replace(old_method_name, ~r/\Ais_/, "")
    if String.ends_with?(new_method_name, "?"), do: new_method_name, else: new_method_name <> "?"
  end

  def patch_call(%{"check" => "Credo.Check.Readability.PredicateFunctionNames"} = issue) do
    %{
      "check" => "Credo.Check.Readability.PredicateFunctionNames",
      "filename" => filename,
      "column" => column,
      "column_end" => column_end,
      "line_no" => line_no,
      "trigger" => method_name
    } = issue

    assert String.starts_with?(method_name, "is_")
    new_method_name = build_new_method_name(method_name)

    IO.puts("Replacing #{method_name} by #{new_method_name} in #{filename}:#{line_no}")

    content =
      filename
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index()
      |> Enum.map(fn {line, index} ->
        if index == line_no - 1 do
          # ensure we're seeing the same thing as Credo
          assert String.slice(line, (column - 1)..(column_end - 2)) == method_name
          line |> String.replace(method_name, new_method_name)
        else
          line
        end
      end)
      |> Enum.join("\n")

    File.write!(filename, content)
  end
end

file
|> File.read!()
|> Jason.decode!()
|> Map.get("issues")
|> Enum.filter(fn x -> x["check"] == "Credo.Check.Readability.PredicateFunctionNames" end)
|> Enum.each(fn x -> Patcher.patch_call(x) end)
