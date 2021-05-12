defmodule Transport.CommentsChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.{Datasets, Discussions}
  alias Mailjet.Client
  alias DB.{Dataset, Repo}
  import TransportWeb.Router.Helpers
  import Ecto.Query
  require Logger

  def check_for_new_comments() do
    datasets_with_new_comments =
      Dataset
      |> where([d], d.is_active == true)
      |> select([:id, :datagouv_id, :latest_data_gouv_comment_timestamp])
      |> limit(10)
      |> Repo.all()
      |> Enum.map(fn %{id: id, datagouv_id: datagouv_id, latest_data_gouv_comment_timestamp: ts} ->
        IO.inspect(datagouv_id)

        updated_ts =
          datagouv_id
          |> Discussions.get()
          |> Discussions.latest_comment_timestamp()

        case {updated_ts, ts} do
          {nil, _} ->
            nil

          {updated_ts, nil} ->
            handle_new_comment(id, datagouv_id, updated_ts)
            datagouv_id

          {updated_ts, ts} ->
            if NaiveDateTime.diff(updated_ts, ts) > 1 do
              handle_new_comment(id, datagouv_id, updated_ts)
              datagouv_id
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    send_email(datasets_with_new_comments)
  end

  def handle_new_comment(id, datagouv_id, timestamp) do
    with {:ok, changeset} <-
           Dataset.changeset(%{
             "id" => id,
             "datagouv_id" => datagouv_id,
             "latest_data_gouv_comment_timestamp" => timestamp
           }) do
      Repo.update(changeset)
    end
  end

  def send_email(_datasets) do
    nil
  end
end
