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

    line_number = get_line_number(plug, plug_opts)
    file_path = get_file_path(plug)

    IO.puts("#{file_path}:#{line_number}")
  rescue
    _ -> IO.puts("function definition not found")
  end

  def get_file_path(module_name) do
    [compile_infos] = Keyword.get_values(module_name.module_info(), :compile)
    [source] = Keyword.get_values(compile_infos, :source)
    source
  end

  def get_line_number(module, function_name) do
    {_, _, _, _, _, _, functions_list} = Code.fetch_docs(module)

    row =
      functions_list |> Enum.find(fn {{type, name, _}, _, _, _, _} -> type == :function and name == function_name end)

    {_, line, _, _, _} = row
    line
  end
end
