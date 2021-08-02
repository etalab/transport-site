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

  # NOTE: at time of writing, the timestamp on LogsValidation
  # is only accurate to the second, so we have to mimic that here
  # or we'll get test errors
  @some_datetime ~U[2021-07-15 14:17:06Z]

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
