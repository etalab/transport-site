defmodule Transport.DataValidator.CeleryTaskTest do
  use ExUnit.Case, async: false
  alias Transport.DataValidator.CeleryTask

  test "apply" do
    assert {:error, "task not found"} == CeleryTask.apply(nil)

    assert {:ok, %CeleryTask{task_id: "1",
                             status: "DOWNLOADED",
                             result: %{},
                             date_done: "today",
                             traceback: %{},
                             children: []}
      } = CeleryTask.apply(%{"_id" => "1",
                             "status" => "DOWNLOADED",
                             "result" => "{}",
                             "date_done" => "today",
                             "traceback" => "{}",
                             "children" => "[]"})
  end
end
