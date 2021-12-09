defmodule DB.BreakingNews do
  @moduledoc """
  Store a message to be displayed on the site home page.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.{Changeset, Query}

  typed_schema "breaking_news" do
    field(:level, :string)
    field(:msg, :string)
  end

  @spec get_breaking_news :: %{optional(:level) => any, optional(:msg) => any}
  def get_breaking_news do
    DB.BreakingNews
    |> limit(1)
    |> DB.Repo.one()
    |> case do
      nil -> %{}
      %{level: level, msg: msg} -> %{level: level, msg: msg}
    end
  end

  @spec set_breaking_news(map()) :: {:ok, any()} | {:error, any()}
  def set_breaking_news(%{msg: ""}) do
    DB.BreakingNews |> DB.Repo.delete_all()
    {:ok, "message deleted"}
  end

  def set_breaking_news(%{level: level, msg: msg}) do
    DB.BreakingNews |> DB.Repo.delete_all()

    %DB.BreakingNews{}
    |> change(%{level: level, msg: msg})
    |> DB.Repo.insert()
  end
end
