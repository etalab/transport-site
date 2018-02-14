defmodule Transport.DataValidation.Commands.ValidateFeedSource do
  @moduledoc """
  Command for creating a feed source.

  ## Examples

      iex> %{project: %Project{id: "1"}, feed_source: %FeedSource{id: "1", url: "gtfs.zip"}}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:ok, %ValidateFeedSource{project: %Project{id: "1"}, feed_source: %FeedSource{id: "1", url: "gtfs.zip"}}}

      iex> %{project: %Project{}, feed_source: %FeedSource{id: "1", url: "gtfs.zip"}}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:error, [{:error, :project, :by, "must exist"}]}

      iex> %{feed_source: %FeedSource{id: "1", url: "gtfs.zip"}}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:error, [
        {:error, :project, :by, "must be a project"},
        {:error, :project, :by, "must exist"}
      ]}

      iex> %{project: %Project{id: "1"}, feed_source: %FeedSource{url: "gtfs.zip"}}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:error, [{:error, :feed_source, :by, "must exist"}]}

      iex> %{project: %Project{id: "1"}, feed_source: %FeedSource{id: "1"}}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:error, [{:error, :feed_source, :by, "must have a url"}]}

      iex> %{project: %Project{id: "1"}}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:error, [
        {:error, :feed_source, :by, "must be a feed source"},
        {:error, :feed_source, :by, "must exist"},
        {:error, :feed_source, :by, "must have a url"}
      ]}

      iex> %{}
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      {:error, [
        {:error, :feed_source, :by, "must be a feed source"},
        {:error, :feed_source, :by, "must exist"},
        {:error, :feed_source, :by, "must have a url"},
        {:error, :project, :by, "must be a project"},
        {:error, :project, :by, "must exist"}
      ]}

      iex> nil
      ...> |> ValidateFeedSource.new
      ...> |> ValidateFeedSource.validate
      ** (RuntimeError) second argument must be a map or keyword list

  """

  defstruct [:project, :feed_source]

  use ExConstructor
  use Vex.Struct
  alias Transport.DataValidation.Aggregates.{Project, FeedSource}

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
    project: Project.t,
    feed_source: FeedSource.t
  }

  validates :project,
    by: &__MODULE__.validate_project_type/1,
    by: &__MODULE__.validate_project_existance/1

  validates :feed_source,
    by: &__MODULE__.validate_feed_source_type/1,
    by: &__MODULE__.validate_feed_source_existance/1,
    by: &__MODULE__.validate_feed_source_url/1

  def validate_project_type(%Project{}), do: :ok
  def validate_project_type(_), do: {:error, "must be a project"}

  def validate_project_existance(%Project{} = %{id: id}) when is_binary(id), do: :ok
  def validate_project_existance(_), do: {:error, "must exist"}

  def validate_feed_source_type(%FeedSource{}), do: :ok
  def validate_feed_source_type(_), do: {:error, "must be a feed source"}

  def validate_feed_source_existance(%FeedSource{} = %{id: id}) when is_binary(id), do: :ok
  def validate_feed_source_existance(_), do: {:error, "must exist"}

  def validate_feed_source_url(%FeedSource{} = %{url: url}) when is_binary(url), do: :ok
  def validate_feed_source_url(_), do: {:error, "must have a url"}
end
