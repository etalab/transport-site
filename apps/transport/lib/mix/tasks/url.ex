defmodule Mix.Tasks.Url do
  @moduledoc """
  Experimental task : given a URL, this tasks looks for the corresponding controller function definition, and gives the function's file name and line number

  mix url http://0.0.0.0:5000/datasets?type=public-transit
  #=> ../transport/lib/transport_web/controllers/dataset_controller.ex:12

  mix url https://transport.data.gouv.fr/resources/8119#validation-report
  #=> ../transport/lib/transport_web/controllers/resource_controller.ex:12
  """

  use Mix.Task

  def run([url]) do
    %{path: path} = URI.parse(url)
    %{plug: plug, plug_opts: plug_opts} = Phoenix.Router.route_info(TransportWeb.Router, "GET", path, "")

    module_name = plug |> Atom.to_string() |> String.replace("Elixir.", "")

    line_number = get_line_number(plug, plug_opts)

    file =
      "../**/*.ex"
      |> Path.wildcard()
      |> Enum.find(fn file -> file_contains_module_def?(file, module_name) end)

    IO.puts("#{file}:#{line_number}")
  rescue
    _ -> IO.puts("function definition not found")
  end

  def file_contains_module_def?(file, module_name) do
    content = File.read!(file)
    String.contains?(content, "defmodule #{module_name} do")
  end

  def get_line_number(module, function_name) do
    {_, _, _, _, _, _, functions_list} = Code.fetch_docs(module)

    row =
      functions_list |> Enum.find(fn {{type, name, _}, _, _, _, _} -> type == :function and name == function_name end)

    {_, line, _, _, _} = row
    line
  end
end
