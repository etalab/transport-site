defmodule Transport.Jobs.NewDatagouvDatasetsJob do
  @moduledoc """
  This job looks at datasets that have been created recently on data.gouv.fr
  and tries to determine if it should be added on the NAP.
  It sends the list of these datasets by email.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  alias Transport.Shared.Schemas.Wrapper, as: Schemas

  @rules [
           %{
             category: "Transport en commun",
             schemas: MapSet.new([]),
             tags:
               MapSet.new([
                 "bus",
                 "deplacements",
                 "déplacements",
                 "horaires",
                 "mobilite",
                 "mobilité",
                 "temps-reel",
                 "temps-réel",
                 "transport",
                 "transports"
               ]),
             formats: MapSet.new(["gtfs", "netex", "gtfs-rt", "gtfsrt", "siri", "ssim"])
           },
           %{
             category: "Freefloating",
             schemas: MapSet.new([]),
             tags:
               MapSet.new([
                 "autopartage",
                 "freefloating",
                 "trottinette",
                 "vls",
                 "scooter",
                 "libre-service",
                 "libre service",
                 "scooter"
               ]),
             formats: MapSet.new(["gbfs"])
           },
           %{
             category: "Vélo et stationnements",
             schemas: [
               "etalab/schema-amenagements-cyclables",
               "etalab/schema-stationnement-cyclable",
               "etalab/schema-stationnement",
               "etalab/schema-comptage-mobilites"
             ],
             tags: MapSet.new(["cyclable", "parking", "stationnement", "velo", "vélo"]),
             formats: MapSet.new([])
           },
           %{
             category: "Covoiturage et ZFE",
             schemas: ["etalab/schema-lieux-covoiturage", "etalab/schema-zfe"],
             tags: MapSet.new(["covoiturage", "zfe"]),
             formats: MapSet.new([])
           },
           %{
             category: "IRVE",
             schemas: ["etalab/schema-irve-statique", "etalab/schema-irve-dynamique"],
             tags:
               MapSet.new([
                 "infrastructure de recharge",
                 "borne de recharge",
                 "irve",
                 "sdirve",
                 "électrique",
                 "electrique"
               ]),
             formats: MapSet.new([])
           }
         ]
         |> Enum.map(fn %{category: category, schemas: schemas, tags: %MapSet{}, formats: %MapSet{}} = rule ->
           if Mix.env() == :prod do
             unless Enum.all?(schemas, &(&1 in Map.keys(Schemas.transport_schemas()))) do
               raise "`#{category}` has invalid schemas: #{inspect(schemas)}"
             end
           end

           rule
         end)

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    filtered_datasets(datagouv_datasets(), inserted_at)
    |> match_for_rules()
    |> send_emails(inserted_at)
  end

  def rules, do: @rules

  def filtered_datasets(datasets, %DateTime{} = inserted_at) do
    dataset_ids = DB.Dataset.base_query() |> select([dataset: d], d.datagouv_id) |> DB.Repo.all()

    Enum.filter(datasets, fn dataset ->
      not_on_platform = dataset["id"] not in dataset_ids

      created_recently =
        after_datetime?(get_in(dataset, ["internal", "created_at_internal"]), starting_date(inserted_at))

      not_on_platform and created_recently
    end)
  end

  def starting_date(%DateTime{} = inserted_at) do
    DateTime.add(inserted_at, window(DateTime.to_date(inserted_at)), :day)
  end

  @doc """
  iex> window(~D[2024-04-01])
  -3
  iex> window(~D[2024-04-02])
  -1
  iex> window(~D[2024-04-03])
  -1
  """
  def window(%Date{} = inserted_at) do
    if inserted_at |> Date.day_of_week() == 1 do
      -3
    else
      -1
    end
  end

  def after_datetime?(created_at, %DateTime{} = dt_limit) when is_binary(created_at) do
    {:ok, datetime, 0} = DateTime.from_iso8601(created_at)
    DateTime.compare(datetime, dt_limit) == :gt
  end

  @doc """
  Useful to ignore specific datasets/organizations.

  iex> ignore_dataset?(%{"organization" => %{"id" => "5a83f81fc751df6f8573eb8a"}, "title" => "BDTOPO© - Chefs-Lieux pour le département de l'Eure-et-Loir"})
  true
  """
  def ignore_dataset?(%{"organization" => %{"id" => "5a83f81fc751df6f8573eb8a"}, "title" => title}) do
    String.contains?(title, "BDTOPO")
  end

  def ignore_dataset?(%{}), do: false

  def dataset_is_relevant?(%{} = dataset, rule) do
    if ignore_dataset?(dataset) do
      false
    else
      match_on_dataset =
        [tags_is_relevant?(dataset, rule), description_is_relevant?(dataset, rule), title_is_relevant?(dataset, rule)]
        |> Enum.any?()

      match_on_resources =
        dataset |> Map.fetch!("resources") |> Enum.any?(&resource_is_relevant?(&1, rule))

      match_on_dataset or match_on_resources
    end
  end

  defp datagouv_datasets do
    url =
      Path.join(Application.fetch_env!(:transport, :datagouvfr_site), "/api/1/datasets/?sort=-created&page_size=500")

    %HTTPoison.Response{status_code: 200, body: body} =
      Transport.Shared.Wrapper.HTTPoison.impl().get!(url, [], timeout: 30_000, recv_timeout: 30_000)

    body |> Jason.decode!() |> Map.fetch!("data")
  end

  defp match_for_rules(datasets) do
    for dataset <- datasets, rule <- @rules, dataset_is_relevant?(dataset, rule) do
      {rule.category, dataset}
    end
  end

  defp send_emails([], %DateTime{}), do: :ok

  defp send_emails(matches, inserted_at) do
    duration = window(DateTime.to_date(inserted_at)) * -24

    matches
    |> Enum.group_by(fn {category, _} -> category end, fn {_, dataset} -> dataset end)
    |> Enum.each(fn {category, datasets} ->
      rule = Enum.find(@rules, &(&1.category == category))

      Transport.AdminNotifier.new_datagouv_datasets(category, datasets, rule_explanation(rule), duration)
      |> Transport.Mailer.deliver()
    end)
  end

  def rule_explanation(%{schemas: schemas, tags: tags, formats: formats}) do
    join_or_empty = fn values ->
      if Enum.empty?(values) do
        "<vide>"
      else
        Enum.join(values, ", ")
      end
    end

    """
    <p>Règles utilisées pour identifier ces jeux de données :</p>
    <ul>
      <li>Formats : #{join_or_empty.(formats)}</li>
      <li>Schémas : #{join_or_empty.(schemas)}</li>
      <li>Mots-clés/tags : #{join_or_empty.(tags)}</li>
    </ul>
    """
  end

  defp title_is_relevant?(%{"title" => title}, rule), do: string_matches?(title, rule)
  defp description_is_relevant?(%{"description" => description}, rule), do: string_matches?(description, rule)

  defp string_matches?(nil, _rule), do: false

  defp string_matches?(str, %{formats: formats, tags: tags} = _rule) when is_binary(str) do
    str
    |> String.downcase()
    |> String.split(" ")
    |> MapSet.new()
    |> MapSet.intersection(MapSet.union(formats, tags))
    |> MapSet.size() > 0
  end

  defp tags_is_relevant?(%{"tags" => tags} = _dataset, rule) do
    tags |> Enum.map(&string_matches?(String.downcase(&1), rule)) |> Enum.any?()
  end

  defp resource_is_relevant?(%{} = resource, rule) do
    Enum.any?([
      resource_format_is_relevant?(resource, rule),
      resource_schema_is_relevant?(resource, rule),
      description_is_relevant?(resource, rule)
    ])
  end

  defp resource_format_is_relevant?(%{"format" => nil}, _rule), do: false

  defp resource_format_is_relevant?(%{"format" => format}, %{formats: formats} = _rule) do
    MapSet.member?(formats, String.downcase(format))
  end

  defp resource_schema_is_relevant?(%{"schema" => %{"name" => schema_name}}, %{schemas: schemas} = _rule) do
    schema_name in schemas
  end

  defp resource_schema_is_relevant?(%{}, _rule), do: false
end
