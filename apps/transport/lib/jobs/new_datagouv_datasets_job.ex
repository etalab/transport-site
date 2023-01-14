defmodule Transport.Jobs.NewDatagouvDatasetsJob do
  @moduledoc """
  This job looks at datasets that have been created recently on data.gouv.fr
  and tries to determine if it should be added on the NAP.
  It sends the list of these datasets by email.
  """
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]
  import Ecto.Query
  alias Transport.Shared.Schemas.Wrapper, as: Schemas

  @relevant_tags MapSet.new([
                   "autopartage",
                   "bus",
                   "covoiturage",
                   "cyclable",
                   "deplacements",
                   "déplacements",
                   "freefloating",
                   "horaires",
                   "mobilite",
                   "mobilité",
                   "parking",
                   "stationnement",
                   "temps-reel",
                   "transport",
                   "transports",
                   "trottinette",
                   "velo",
                   "vls",
                   "vélo",
                   "zfe"
                 ])
  @relevant_formats MapSet.new(["gtfs", "netex", "gbfs", "gtfs-rt", "gtfsrt", "siri"])

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    %HTTPoison.Response{status_code: 200, body: body} =
      Transport.Shared.Wrapper.HTTPoison.impl().get!(
        Path.join(Application.fetch_env!(:transport, :datagouvfr_site), "/api/1/datasets/?sort=-created&page_size=500"),
        [],
        timeout: 30_000,
        recv_timeout: 30_000
      )

    %{"data" => datasets} = Jason.decode!(body)
    datasets = filtered_datasets(datasets, inserted_at)

    unless Enum.empty?(datasets) do
      Transport.EmailSender.impl().send_mail(
        "transport.data.gouv.fr",
        Application.get_env(:transport, :contact_email),
        Application.get_env(:transport, :bizdev_email),
        Application.get_env(:transport, :contact_email),
        "Nouveaux jeux de données à référencer - data.gouv.fr",
        """
        Bonjour,

        Les jeux de données suivants ont été ajoutés sur data.gouv.fr dans les dernières 24h et sont susceptibles d'avoir leur place sur le PAN :

        #{Enum.map_join(datasets, "\n", &link_and_name/1)}

        ---
        Vous pouvez consulter et modifier les règles de cette tâche : https://github.com/etalab/transport-site/blob/master/apps/transport/lib/jobs/new_datagouv_datasets_job.ex
        """,
        ""
      )
    end

    :ok
  end

  def link_and_name(%{"title" => title, "page" => page}) do
    ~s(* #{title} - #{page})
  end

  def filtered_datasets(datasets, %DateTime{} = inserted_at) do
    a_day_ago = DateTime.add(inserted_at, -1, :day)
    dataset_ids = DB.Dataset.base_query() |> select([dataset: d], d.datagouv_id) |> DB.Repo.all()

    Enum.filter(datasets, fn dataset ->
      dataset["id"] not in dataset_ids and after_datetime?(dataset["created_at"], a_day_ago) and
        dataset_is_relevant?(dataset)
    end)
  end

  def after_datetime?(created_at, %DateTime{} = dt_limit) when is_binary(created_at) do
    # data.gouv.fr does not include the timezone (trailing Z) but these are UTC datetimes
    created_at = String.replace_trailing(created_at, "Z", "") <> "Z"
    {:ok, datetime, 0} = DateTime.from_iso8601(created_at)
    DateTime.compare(datetime, dt_limit) == :gt
  end

  def dataset_is_relevant?(%{} = dataset) do
    match_on_dataset =
      [&tags_is_relevant?/1, &description_is_relevant?/1, &title_is_relevant?/1]
      |> Enum.map(& &1.(dataset))
      |> Enum.any?()

    match_on_resources =
      dataset
      |> Map.fetch!("resources")
      |> Enum.map(&resource_is_relevant?/1)
      |> Enum.any?()

    match_on_dataset or match_on_resources
  end

  defp title_is_relevant?(%{"title" => title}), do: string_matches?(title)
  defp description_is_relevant?(%{"description" => description}), do: string_matches?(description)

  defp string_matches?(nil), do: false

  defp string_matches?(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.split(" ")
    |> MapSet.new()
    |> MapSet.intersection(MapSet.union(@relevant_formats, @relevant_tags))
    |> MapSet.size() > 0
  end

  defp tags_is_relevant?(%{"tags" => tags}) do
    tags |> Enum.map(&string_matches?(String.downcase(&1))) |> Enum.any?()
  end

  defp resource_is_relevant?(%{} = resource) do
    [&resource_format_is_relevant?/1, &resource_schema_is_relevant?/1, &description_is_relevant?/1]
    |> Enum.map(& &1.(resource))
    |> Enum.any?()
  end

  defp resource_format_is_relevant?(%{"format" => nil}), do: false

  defp resource_format_is_relevant?(%{"format" => format}) do
    MapSet.member?(@relevant_formats, String.downcase(format))
  end

  defp resource_schema_is_relevant?(%{"schema" => %{"name" => "etalab/schema-irve"}}), do: false

  defp resource_schema_is_relevant?(%{"schema" => %{"name" => schema_name}}) do
    schema_name in Map.keys(Schemas.transport_schemas())
  end

  defp resource_schema_is_relevant?(%{}), do: false
end
