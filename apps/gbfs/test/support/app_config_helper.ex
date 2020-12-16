defmodule AppConfigHelper do
  @moduledoc """
  A way to temporarily change Application config. Make sure to only use this
  with "async: false" tests
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  def change_app_config_temporarily(config_name, config_key, value) do
    old_value = Application.fetch_env!(config_name, config_key)
    on_exit(fn -> Application.put_env(config_name, config_key, old_value) end)
    Application.put_env(config_name, config_key, value)
  end

  def enable_cache do
    change_app_config_temporarily(:gbfs, :disable_page_cache, false)
    # clear the cache since some element can still be there
    on_exit(fn -> Cachex.clear(:gbfs) end)
  end
end
