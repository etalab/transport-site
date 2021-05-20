defmodule Transport.CommentsCheckerTest do
  use ExUnit.Case, async: false
  alias Transport.CommentsChecker
  alias DB.{Dataset, Repo}
  import TransportWeb.Factory
  import Mock

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def assert_dataset_ts(id, timestamp) do
    %{latest_data_gouv_comment_timestamp: db_ts} = Dataset |> Repo.get!(id)

    case timestamp do
      nil ->
        assert is_nil(db_ts)

      timestamp ->
        timestamp = NaiveDateTime.from_iso8601!(timestamp)
        assert NaiveDateTime.diff(timestamp, db_ts) < 1
    end
  end

  test "check for new comments on data.gouv.fr" do
    %{id: dataset_id} = insert(:dataset, title: "dataset 1")

    # when the dataset is created, no comment timestamp is stored
    assert_dataset_ts(dataset_id, nil)

    get_mock = fn url, [], _ ->
      {:ok,
       %{
         "data" => [
           %{
             "id" => "discussion_id_1",
             "discussion" => [
               %{"posted_on" => "2020-01-01T12:00:00.000000", "content" => "commentaire 1"}
             ]
           }
         ]
       }}
    end

    send_mail_mock = fn _, _, _, _, _, _, _ ->
      {:ok, "envoyé !"}
    end

    with_mock Datagouvfr.Client.API, get: get_mock do
      with_mock Mailjet.Client, send_mail: send_mail_mock do
        number_new_comments = CommentsChecker.check_for_new_comments()

        assert number_new_comments == 1
        assert_called_exactly(Mailjet.Client.send_mail(:_, :_, :_, :_, :_, :_, :_), 1)
        assert_dataset_ts(dataset_id, "2020-01-01T12:00:00.000000")

        # second run : we shouldn't find new comment
        number_new_comments_2 = CommentsChecker.check_for_new_comments()
        assert number_new_comments_2 == 0
        # no additionnal mail is sent
        assert_called_exactly(Mailjet.Client.send_mail(:_, :_, :_, :_, :_, :_, :_), 1)
        # timestamp has not changed
        assert_dataset_ts(dataset_id, "2020-01-01T12:00:00.000000")
      end
    end

    # we add a new comment
    get_mock = fn url, [], _ ->
      {:ok,
       %{
         "data" => [
           %{
             "id" => "discussion_id_1",
             "discussion" => [
               %{"posted_on" => "2020-01-01T12:00:00.000000", "content" => "commentaire 1"},
               %{"posted_on" => "2021-01-01T12:00:00.000000", "content" => "commentaire 2"}
             ]
           }
         ]
       }}
    end

    with_mock Datagouvfr.Client.API, get: get_mock do
      with_mock Mailjet.Client, send_mail: send_mail_mock do
        number_new_comments = CommentsChecker.check_for_new_comments()

        assert number_new_comments == 1
        assert_called_exactly(Mailjet.Client.send_mail(:_, :_, :_, :_, :_, :_, :_), 1)
        assert_dataset_ts(dataset_id, "2021-01-01T12:00:00.000000")
      end
    end
  end
end
