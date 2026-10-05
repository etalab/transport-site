defmodule TransportWeb.Components.Pagination do
  @moduledoc """
  Pagination links for a `Scrivener.Page`.

  Links point to the current path and keep its query parameters.
  """
  use TransportWeb, :html

  @distance 5

  attr(:conn, Plug.Conn, required: true)
  attr(:page, Scrivener.Page, required: true)
  attr(:params, :list, default: [], doc: "query parameters overriding the current ones, `nil` removes one")
  attr(:anchor, :string, default: nil)

  def pagination(%{page: %Scrivener.Page{total_pages: total_pages}} = assigns) when total_pages <= 1 do
    ~H""
  end

  def pagination(assigns) do
    ~H"""
    <nav aria-label="Page navigation">
      <ul class="pagination">
        <li :for={link <- links(@conn, @page, @params, @anchor)} class={link.active && "active"}>
          <span :if={link.label == :ellipsis}>&hellip;</span>
          <a :if={link.label != :ellipsis} href={link.href} rel={link.rel}>{link.label}</a>
        </li>
      </ul>
    </nav>
    """
  end

  defp links(conn, %Scrivener.Page{page_number: current} = page, params, anchor) do
    for {label, number} <- page_numbers(page) do
      other_page? = number not in [nil, current]

      %{
        label: label,
        active: number == current,
        href: if(other_page?, do: page_url(conn, params, anchor, number)),
        rel: if(other_page?, do: rel(current, number))
      }
    end
  end

  defp page_numbers(%Scrivener.Page{page_number: current, total_pages: total}) do
    first = max(min(current, total) - @distance, 1)
    last = min(current + @distance, total)

    Enum.concat([
      if(current > 1, do: [{"<<", current - 1}], else: []),
      if(first > 1, do: [{1, 1}], else: []),
      if(first > 2, do: [{:ellipsis, nil}], else: []),
      Enum.map(first..last//1, &{&1, &1}),
      if(last < total - 1, do: [{:ellipsis, nil}], else: []),
      if(last < total, do: [{total, total}], else: []),
      if(current < total, do: [{">>", current + 1}], else: [])
    ])
  end

  defp rel(current, number) when number == current + 1, do: "next"
  defp rel(current, number) when number == current - 1, do: "prev"
  defp rel(_current, _number), do: "canonical"

  defp page_url(%Plug.Conn{request_path: path, query_params: query_params}, params, anchor, number) do
    query =
      query_params
      |> Map.drop(["page"])
      |> Map.reject(&match?({"q", ""}, &1))
      |> Map.merge(Map.new(params, fn {key, value} -> {to_string(key), value} end))
      |> Map.reject(&match?({_, nil}, &1))
      |> Enum.sort()
      |> Kernel.++(if number > 1, do: [{"page", number}], else: [])
      |> Plug.Conn.Query.encode()

    url = if query == "", do: path, else: path <> "?" <> query
    if anchor, do: url <> "#" <> anchor, else: url
  end
end
