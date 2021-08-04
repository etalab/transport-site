defmodule Transport.ModifiedAtCalculationTest do
  use ExUnit.Case, async: true
  import TransportWeb.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def add_hours(dt, hours), do: DateTime.add(dt, 60 * 60 * hours, :second)

  # quick method to build logs in concise fashion
  def build_logs(enum) do
    enum
    |> Enum.map(fn {reason, timestamp} ->
      build(:validation_log, skipped_reason: reason, timestamp: timestamp)
    end)
  end

  def compute_modified_at(r) do
    Transport.ModifiedAtCalculation.compute_last_modified_at_based_on_content_hash_change(r)
  end

  defmodule BigQueryThing do
    import Ecto.Query

    def logs_validation_query() do
      from(l in DB.LogsValidation,
      distinct: [asc: l.resource_id],
      select: %{resource_id: l.resource_id, log_timestamp: l.timestamp},
      where: l.skipped_reason == "content hash has changed",
      order_by: [desc: l.timestamp]
    )
    end

    def update_content_hash_modified_at_query() do
      # keyword syntax is not supported for this feature at bottom of
      # https://hexdocs.pm/ecto/Ecto.Query.html#with_cte/3-expression-examples
      DB.Resource
      |> with_cte("latest_timestamps", as: ^logs_validation_query())
      |> join(:inner, [r], l in "latest_timestamps", on: r.id == l.resource_id)
      |> update(set: [content_hash_last_modified_at: fragment("log_timestamp")])
      # TODO: only update if new value is more recent than old value. This will ensure
      # we do not lower the timestamp, in the events of the logs being deleted
    end

    def update_content_has_modified_at!() do
      update_content_hash_modified_at_query()
      |> DB.Repo.update_all([])
    end
  end

  # NOTE: at time of writing, the timestamp on LogsValidation
  # is only accurate to the second, so we have to mimic that here
  # or we'll get test errors
  @some_datetime ~U[2021-07-15 14:17:06Z]

  @tag :focus
  test "stuff" do
    BigQueryThing.update_content_has_modified_at!()
  end

  test "takes the most recent 'content has has changed' timestamp" do
    assert compute_modified_at(
             insert(:resource,
               logs_validation:
                 build_logs([
                   {"content hash has changed", _d1 = add_hours(@some_datetime, 1)},
                   {"content hash has changed", d2 = add_hours(@some_datetime, 3)},
                   {"some other reason", _d3 = add_hours(@some_datetime, 4)}
                 ])
             )
           ) == d2
  end

  # NOTE: logs are removed after a while, and could also be non existing in the first place
  test "returns nil if no logs are available" do
    assert compute_modified_at(insert(:resource, logs_validation: [])) == nil
  end

  test "works no matter the order" do
    assert compute_modified_at(
             insert(:resource,
               logs_validation:
                 build_logs([
                   {"content hash has changed", d1 = add_hours(@some_datetime, 3)},
                   {"content hash has changed", _d2 = add_hours(@some_datetime, 1)}
                 ])
             )
           ) == d1
  end
end
