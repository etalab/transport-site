defmodule Transport.CommentsChecker do
  @moduledoc """
  Check for new comments posted on data.gouv.fr for datasets referenced on the PAN
  Send an email to the team with the new comments and a link to them.
  """
  alias Datagouvfr.Client.Discussions
  alias DB.{Dataset, Repo}
  import Ecto.Query
  require Logger

  def check_for_new_comments do
    discussions_infos =
      Dataset
      |> where([d], d.is_active == true)
      |> select([:id, :datagouv_id, :latest_data_gouv_comment_timestamp])
      |> Repo.all()
      |> Enum.map(fn %{datagouv_id: datagouv_id, latest_data_gouv_comment_timestamp: current_ts} = dataset ->
        comments =
          datagouv_id
          |> Discussions.get()
          |> Discussions.add_discussion_id_to_comments()
          |> Discussions.comments_posted_after(current_ts)

        title = get_dataset_title(datagouv_id)

        {dataset, datagouv_id, title, comments}
      end)

    number_new_comments =
      discussions_infos |> Enum.reduce(0, fn {_, _, _, comments}, acc -> acc + Enum.count(comments) end)

    case number_new_comments do
      0 ->
        Logger.info("no new comment posted since last check")

      _ ->
        Logger.info("#{number_new_comments} new comment(s), sending an email to the team")

        email_content =
          Phoenix.View.render_to_string(TransportWeb.EmailView, "index.html", discussions_infos: discussions_infos)

        Mailjet.Client.send_mail(
          "transport.data.gouv.fr",
          "contact@transport.beta.gouv.fr",
          "contact@transport.beta.gouv.fr",
          "#{number_new_comments} nouveaux commentaires sur data.gouv.fr",
          "",
          email_content,
          false
        )

        update_all_datasets_ts(discussions_infos)
    end

    number_new_comments
  end

  def update_all_datasets_ts(discussions_infos) do
    discussions_infos
    |> Enum.map(fn {dataset, datagouv_id, _, comments} ->
      comments
      |> Discussions.comments_latest_timestamp()
      |> case do
        nil ->
          nil

        # ecto does not want to store microseconds
        datetime ->
          ts = NaiveDateTime.truncate(datetime, :second)
          update_dataset_ts(dataset, datagouv_id, ts)
      end
    end)
  end

  def update_dataset_ts(dataset, _datagouv_id, timestamp) do
    changeset = Ecto.Changeset.change(dataset, %{latest_data_gouv_comment_timestamp: timestamp})
    Repo.update(changeset)
  end

  def get_dataset_title(datagouv_id) do
    Dataset
    |> where([d], d.datagouv_id == ^datagouv_id)
    |> select([d], d.spatial)
    |> Repo.one()
  end
end
