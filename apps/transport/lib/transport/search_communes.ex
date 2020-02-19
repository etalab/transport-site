defmodule Transport.SearchCommunes do
  @moduledoc """
  This modules loads the communes in memory and provides search on it
  """

  use Agent
  alias DB.{Commune, Repo}
  import Ecto.Query

  def start_link(_initial_value) do
    Agent.start_link(&load_communes/0, name: __MODULE__)
  end

  def search(term) do
    Agent.get(__MODULE__, __MODULE__, :filter, [term])
  end

  @doc """
  Filter list of communes by a search term
  ## Examples
  iex> l = [%{nom: "Paris", insee: "75116"}, %{nom: "Paris-l'Hôpital", insee: "71343"}]
  ...> |> Enum.map(&Transport.SearchCommunes.make_search_struct/1)
  [
    %{insee: "75116", nom: "Paris", normalized_nom: "paris"},
    %{insee: "71343", nom: "Paris-l'Hôpital", normalized_nom: "parislhopital"}
  ]
  iex> Transport.SearchCommunes.filter(l, "paris")
  [
    %{insee: "75116", nom: "Paris", normalized_nom: "paris"},
    %{insee: "71343", nom: "Paris-l'Hôpital", normalized_nom: "parislhopital"}
  ]
  iex> Transport.SearchCommunes.filter(l, "paris 75")
  [
    %{insee: "75116", nom: "Paris", normalized_nom: "paris"},
  ]
  """
  @spec filter([map()], binary()) :: [map()]
  def filter(communes, term) do
    alpha_term = normalize_alpha(term)
    num_term = get_num(term)

    communes
    |> Stream.filter(fn c -> String.starts_with?(c.normalized_nom, alpha_term) end)
    |> Stream.filter(fn c -> search_insee(c, num_term) end)
    |> Enum.to_list()
  end

  @doc """
  Extract, normalize and downcase a string
  ## Examples
  iex> Transport.SearchCommunes.normalize_alpha("Paris")
  "paris"
  iex> Transport.SearchCommunes.normalize_alpha("Paris 75116")
  "paris"
  iex> Transport.SearchCommunes.normalize_alpha("Châteauroux")
  "chateauroux"
  """
  @spec normalize_alpha(binary()) :: binary()
  def normalize_alpha(s) do
    s
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-z]/u, "")
    |> String.downcase()
  end

  @doc """
  Get num part of a string
  ## Examples
  iex> Transport.SearchCommunes.get_num("22")
  "22"
  iex> Transport.SearchCommunes.get_num("Paris 75116")
  "75116"
  iex> Transport.SearchCommunes.get_num("Ajaccio 2A")
  "2A"
  iex> Transport.SearchCommunes.get_num("Ajaccio 2A004")
  "2A004"
  iex> Transport.SearchCommunes.get_num("Ajaccio 2C004")
  "2"
  """
  @spec get_num(binary()) :: binary()
  def get_num(term) do
    case Regex.run(~r/\d([A,B])?\d*/, term) do
      nil -> ""
      [a | _] -> a
    end
  end

  @doc """
  Search for insee code if term is not empty
  ## Examples
  iex> Transport.SearchCommunes.search_insee(%{nom: "paris", insee: "75116"}, "")
  true
  iex> Transport.SearchCommunes.search_insee(%{nom: "paris", insee: "75116"}, "75")
  true
  iex> Transport.SearchCommunes.search_insee(%{nom: "paris", insee: "75116"}, "85")
  false
  """
  @spec search_insee(map(), binary) :: boolean
  def search_insee(_, ""), do: true

  def search_insee(%{insee: insee}, n) do
    String.starts_with?(insee, n)
  end

  @spec make_search_struct(%{nom: binary()}) :: %{nom: binary(), normalized_nom: binary()}
  def make_search_struct(%{nom: nom} = s), do: Map.put(s, :normalized_nom, normalize_alpha(nom))

  @spec load_communes :: [Commune.t()]
  defp load_communes do
    Commune
    |> select([:nom, :insee])
    |> Repo.all()
    |> Enum.map(&make_search_struct/1)
    |> Enum.sort_by(fn c -> byte_size(c.nom) end)
  end
end
