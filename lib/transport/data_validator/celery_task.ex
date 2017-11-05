defmodule Transport.DataValidator.CeleryTask do
  @moduledoc """
    Module to get celerytask from mongoDB
  """

  defstruct [:task_id, :status, :result, :date_done, :traceback, :children]

  def find_one(task_id) do
     :mongo
     |> Mongo.find_one("celery_taskmeta", %{_id: task_id}, pool: DBConnection.Poolboy)
     |> apply()
  end

  def apply(nil) do
    {:error, "task not found"}
  end

  def apply(obj) do
    with {:ok, result}    <- Poison.decode(obj["result"]),
         {:ok, traceback} <- Poison.decode(obj["traceback"]),
         {:ok, children}  <- Poison.decode(obj["children"]) do
      {:ok, %__MODULE__{
          :task_id   => obj["_id"],
          :status    => obj["status"],
          :date_done => obj["date_done"],
          :result    => result,
          :traceback => traceback,
          :children  => children
      }}
    else
      error -> {:error, error}
    end
  end
end
