defmodule Transport.ClimateResilienceBill do
  @moduledoc """
  A module dedicated to handle features related to the article 122
  of the Climate and Resilience bill.
  """
  use Gettext, backend: TransportWeb.Gettext
  @relevant_dataset_types ["public-transit", "vehicles-sharing", "road-data"]

  @doc """
  Should we display the data reuse panel when listing/searching datasets.

  iex> display_data_reuse_panel?(%{"loi-climat-resilience" => "true", "page" => 2})
  true
  iex> display_data_reuse_panel?(%{"type" => "public-transit", "page" => 2})
  true
  iex> display_data_reuse_panel?(%{"type" => "private-parking", "page" => 2})
  false
  """
  @spec display_data_reuse_panel?(map()) :: boolean()
  def display_data_reuse_panel?(%{"loi-climat-resilience" => "true"}), do: true
  def display_data_reuse_panel?(%{"type" => dataset_type}), do: dataset_type in relevant_dataset_types()

  def display_data_reuse_panel?(_), do: false

  # Article 122 loi climat et résilience, will be back
  # https://github.com/etalab/transport-site/issues/3149
  # Temporary message, replace with `data_reuse_message/2` after
  def temporary_data_reuse_message(%{"loi-climat-resilience" => "true"}) do
    dgettext("dataset", "These datasets will be subject to a data reuse obligation.")
  end

  def temporary_data_reuse_message(dataset_type)
      when is_binary(dataset_type) and dataset_type in @relevant_dataset_types do
    temporary_data_reuse_message(%{"type" => dataset_type})
  end

  def temporary_data_reuse_message(%{"type" => dataset_type}) when dataset_type in @relevant_dataset_types do
    dgettext("dataset", "Some datasets in this category will be subject to a data reuse obligation.")
  end

  @doc """
  iex> data_reuse_message(%{"loi-climat-resilience" => "true"}, ~D[2022-12-01])
  "Ces jeux de données font l'objet d'une intégration obligatoire."
  iex> data_reuse_message("public-transit", ~D[2022-12-01])
  "Certaines données de cette catégorie font l'objet d'une intégration obligatoire depuis décembre 2022."
  iex> data_reuse_message("public-transit", ~D[2022-11-01])
  "Certaines données de cette catégorie font l'objet d'une intégration obligatoire à partir de décembre 2022."
  iex> Enum.each(relevant_dataset_types(), & data_reuse_message(&1, Date.utc_today()))
  :ok
  """
  @spec data_reuse_message(binary() | map(), Date.t()) :: binary()
  def data_reuse_message(%{"loi-climat-resilience" => "true"}, %Date{} = _) do
    dgettext("dataset", "These datasets are subject to a data reuse obligation.")
  end

  def data_reuse_message(dataset_type, %Date{} = date) when is_binary(dataset_type) do
    data_reuse_message(%{"type" => dataset_type}, date)
  end

  def data_reuse_message(%{"type" => dataset_type}, %Date{} = date) do
    start_date = start_of_data_reuse_by_type(dataset_type)

    before_after =
      case Date.compare(start_date, date) do
        res when res in [:lt, :eq] -> dgettext("dataset", "since")
        :gt -> dgettext("dataset", "starting from")
      end

    dgettext(
      "dataset",
      "Some datasets in this category are subject to a data reuse obligation %{before_after} %{month}.",
      before_after: before_after,
      month: dates_str(start_date)
    )
  end

  @doc """
  When does data reuse is compulsory for a dataset type?

  iex> start_of_data_reuse_by_type("public-transit")
  ~D[2022-12-01]
  iex> Enum.each(relevant_dataset_types(), &start_of_data_reuse_by_type/1)
  :ok
  """
  @spec start_of_data_reuse_by_type(binary()) :: Date.t()
  def start_of_data_reuse_by_type(type) do
    # See https://www.legifrance.gouv.fr/codes/section_lc/LEGITEXT000023086525/LEGISCTA000046145491
    # Article D1115-18 and Article D1115-19
    Map.fetch!(
      %{
        "road-data" => ~D[2022-08-03],
        "public-transit" => ~D[2022-12-01],
        "vehicles-sharing" => ~D[2023-12-01]
      },
      type
    )
  end

  @doc """
  iex> dates_str(~D[2022-12-01])
  "décembre 2022"
  iex> Enum.each(relevant_dataset_types(), & &1 |> start_of_data_reuse_by_type() |> dates_str())
  :ok
  """
  @spec dates_str(Date.t()) :: binary()
  def dates_str(%Date{} = date) do
    case date do
      ~D[2022-08-03] -> dgettext("dataset", "August 2022")
      ~D[2022-12-01] -> dgettext("dataset", "December 2022")
      ~D[2023-12-01] -> dgettext("dataset", "December 2023")
    end
  end

  @spec relevant_dataset_types() :: [binary()]
  def relevant_dataset_types, do: @relevant_dataset_types
end
