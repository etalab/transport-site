defmodule AppConfigHelper do
  @moduledoc """
  A way to temporarily change Application config. Make sure to only use this
  with "async: false" tests
  """
  def enable_cache do
    change_app_config_temporarily(:gbfs, :disable_page_cache, false)
    # clear the cache since some element can still be there
    ExUnit.Callbacks.on_exit(fn -> Cachex.clear(:gbfs) end)
  end

  def setup_telemetry_handler do
    events = Enum.map([:external, :internal], &[:gbfs, :request, &1])
    events |> Enum.at(1) |> :telemetry.list_handlers() |> Enum.map(& &1.id) |> Enum.each(&:telemetry.detach/1)
    test_pid = self()
    # inspired by https://github.com/dashbitco/broadway/blob/main/test/broadway_test.exs
    :telemetry.attach_many(
      "test-handler-#{System.unique_integer()}",
      events,
      fn name, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end

  def change_app_config_temporarily(config_name, config_key, value) do
    old_value = Application.fetch_env!(config_name, config_key)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(config_name, config_key, old_value) end)
    Application.put_env(config_name, config_key, value)
  end
end
