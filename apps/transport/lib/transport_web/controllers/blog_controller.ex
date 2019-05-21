defmodule TransportWeb.BlogController do
  use TransportWeb, :controller

  def index(conn, _params) do
    articles =
    "lib/transport_web/templates/blog/????_??_??_*.md"
    |> Path.wildcard()
    |> Enum.map(&read_file/1)

    render conn, "index.html", articles: articles
  end

  def page(conn, %{"page" => page}), do: render conn, "article.html", page: page <> ".html"

  def read_file(path) do
    {header, title, image, _} =
      path
      |> File.stream!
      |> Stream.reject(fn l -> l == "\n" end)
      |> Stream.scan({nil, nil, nil, false}, &get_header_title_image/2)
      |> Stream.take_while(fn {_, _, _, t} -> not t end)
      |> Enum.to_list
      |> List.last

    [year|[month|[day|_]]] =
      path
      |> Path.basename
      |> String.split("_")

    image = ~r/\((?<path>.*)\)/ |> Regex.run(image, capture: :all_names) |> List.first()
    article_path =
      path
      |> Path.basename()
      |> String.split(".")
      |> List.first()

    %{
      header: header,
      title: title,
      image: image,
      date: day <> "/" <> month <> "/" <> year,
      path: article_path
    }
  end

  def get_header_title_image(l, {nil, nil, nil, _}), do: {[l], nil, nil, false}
  def get_header_title_image("# " <> title, {h, nil, _, _}), do: {h, title, nil, false}
  def get_header_title_image("![" <> image, {h, t, nil, _}), do: {h, t, image, false}
  def get_header_title_image(l, {h, nil, nil, _}), do: {h ++ [l], nil, nil, false}
  def get_header_title_image(_l, {h, t, i, _}) when not is_nil(i) and not is_nil(t), do: {h, t, i, true}
  def get_header_title_image(_l, {h, t, i, _}) , do: {h, t, i, false}

end
