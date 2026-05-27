defmodule Credo.Check.Custom.NoSystemEnvAtCompileTime do
  @moduledoc "Make sure to keep an env-free compilation (for Elixir releases)."
  use Credo.Check, base_priority: :normal, category: :refactor

  @forbidden ~w(get_env fetch_env fetch_env!)a

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if compile_time_config?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp compile_time_config?(filename) do
    rel = Path.relative_to_cwd(filename)
    String.starts_with?(rel, "config/") and rel != "config/runtime.exs"
  end

  # AST shape of any dotted call `_.<fun>(...args)`:
  #   {{:., _, [_module, fun]}, call_meta, args}
  defp traverse(
         {{:., _, [_module, fun]}, meta, _args} = ast,
         issues,
         issue_meta
       )
       when fun in @forbidden do
    issue =
      format_issue(issue_meta,
        message: "#{fun} forbidden at compile time; move to config/runtime.exs",
        line_no: meta[:line]
      )

    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
end
