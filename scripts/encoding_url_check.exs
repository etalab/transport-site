#! mix run
Code.require_file(__DIR__ <> "/irve/req_custom_cache.exs")

import Ecto.Query

defmodule Downloader do
  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  def get!(url) do
    req = Req.new() |> CustomCache.attach()
    %{body: body, status: 200} = Req.get!(req, url: url, custom_cache_dir: cache_dir())
    body
  end
end

base_url = "https://www.data.gouv.fr"

task = fn dataset ->
  url = base_url <> "/api/1/datasets/#{dataset.datagouv_id}/"
  # IO.puts url
  {dataset.id, Downloader.get!(url)}
end

DB.Dataset
|> where([d], d.is_active == true)
|> DB.Repo.all()
# |> Enum.take(2)
|> Task.async_stream(task, max_concurrency: 20, timeout: :infinity)
|> Enum.map(fn {:ok, {dataset_id, response}} ->
  response["resources"]
  |> Enum.map(fn r ->
    url = r["url"]
    encoded_url = URI.encode(url)
    {encoded_url != url, dataset_id, r["id"], url, encoded_url}
  end)
end)
|> List.flatten()
|> Enum.filter(fn {diff, _, _, _, _} -> diff end)
|> IO.inspect(IEx.inspect_opts())
