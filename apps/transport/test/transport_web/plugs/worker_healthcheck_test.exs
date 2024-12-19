defmodule TransportWeb.Plugs.WorkerHealthcheckTest do
  # async: false is required because we use real in-memory caching in these tests
  use TransportWeb.ConnCase, async: false
  alias TransportWeb.Plugs.WorkerHealthcheck

  setup do
    # Use a real in-memory cache for these tests to test the caching mecanism
    old_value = Application.fetch_env!(:transport, :cache_impl)
    Application.put_env(:transport, :cache_impl, Transport.Cache.Cachex)

    on_exit(fn ->
      Application.put_env(:transport, :cache_impl, old_value)
      Cachex.reset(Transport.Cache.Cachex.cache_name())
    end)

    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "healthy_state?" do
    test "app was started recently, no Oban jobs" do
      assert WorkerHealthcheck.app_started_recently?()
      refute WorkerHealthcheck.oban_attempted_jobs_recently?()
      assert WorkerHealthcheck.healthy_state?()
    end

    test "app was not started recently, Oban jobs have not been attempted recently" do
      datetime = DateTime.add(DateTime.utc_now(), -30, :minute)
      Cachex.put(Transport.Cache.Cachex.cache_name(), WorkerHealthcheck.app_start_datetime_cache_key_name(), datetime)

      refute WorkerHealthcheck.app_started_recently?()
      refute WorkerHealthcheck.oban_attempted_jobs_recently?()
      refute WorkerHealthcheck.healthy_state?()
    end

    test "app was not started recently, Oban jobs have been attempted recently" do
      datetime = DateTime.add(DateTime.utc_now(), -30, :minute)
      Cachex.put(Transport.Cache.Cachex.cache_name(), WorkerHealthcheck.app_start_datetime_cache_key_name(), datetime)

      # A completed job was attempted 55 minutes ago
      Transport.Jobs.ResourceUnavailableJob.new(%{resource_id: 1})
      |> Oban.insert!()
      |> Ecto.Changeset.change(attempted_at: DateTime.add(DateTime.utc_now(), -55, :minute), state: "completed")
      |> DB.Repo.update!()

      refute WorkerHealthcheck.app_started_recently?()
      assert WorkerHealthcheck.oban_attempted_jobs_recently?()
      assert WorkerHealthcheck.healthy_state?()
    end
  end

  describe "call" do
    test "healthy system", %{conn: conn} do
      assert WorkerHealthcheck.app_started_recently?()
      refute WorkerHealthcheck.oban_attempted_jobs_recently?()
      assert WorkerHealthcheck.healthy_state?()

      assert conn |> WorkerHealthcheck.call(if: {__MODULE__, :plug_enabled?}) |> text_response(200)
    end

    test "unhealthy system", %{conn: conn} do
      datetime = DateTime.add(DateTime.utc_now(), -30, :minute)
      Cachex.put(Transport.Cache.Cachex.cache_name(), WorkerHealthcheck.app_start_datetime_cache_key_name(), datetime)

      refute WorkerHealthcheck.app_started_recently?()
      refute WorkerHealthcheck.oban_attempted_jobs_recently?()
      refute WorkerHealthcheck.healthy_state?()

      assert conn |> WorkerHealthcheck.call(if: {__MODULE__, :plug_enabled?}) |> text_response(503)
    end
  end

  def plug_enabled?, do: true
end
