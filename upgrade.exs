file = "credo.json"

Mix.install([
  {:jason, "~> 1.4"}
])

unless File.exists?(file) do
  {_, 0} = System.shell("mix credo --strict --format json 2>&1 credo.json")
end

defmodule Patcher do
  def patch_call(%{"check" => "Credo.Check.Readability.PredicateFunctionNames"} = issue) do
    %{
      "check" => "Credo.Check.Readability.PredicateFunctionNames",
      "filename" => filename,
      "line_no" => line_no,
      "trigger" => method_name
    } = issue
    content = File.read!(filename)
  end
end

file
|> File.read!()
|> Jason.decode!()
|> Map.get("issues")
|> Enum.filter(fn(x) -> x["check"] == "Credo.Check.Readability.PredicateFunctionNames" end)
|> Enum.group_by(&(&1["scope"]))
|> IO.inspect(IEx.inspect_opts)
