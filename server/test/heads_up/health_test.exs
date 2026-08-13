defmodule HeadsUp.HealthTest do
  # async: false — pokes the shared heartbeat table and the ESPN probe cache.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Health, Heartbeat}

  setup do
    Heartbeat.init_table()
    :ets.delete_all_objects(:heads_up_heartbeats)
    # The ESPN probe is cached; clear it so each test controls the answer.
    :persistent_term.erase({Health, :espn})
    on_exit(fn -> :persistent_term.erase({Health, :espn}) end)
    :ok
  end

  describe "heartbeats" do
    test "a worker that has never run reads as nil, not zero" do
      assert Heartbeat.age_seconds(:janitor) == nil
    end

    test "recording makes the age readable" do
      Heartbeat.record(:janitor)
      age = Heartbeat.age_seconds(:janitor)
      assert is_integer(age) and age >= 0
    end
  end

  describe "report/0" do
    test "the database check passes against the real repo" do
      assert %{checks: %{database: %{ok: true}}} = Health.report()
    end

    test "a fresh worker stamp is healthy" do
      Heartbeat.record(:settlement)
      Heartbeat.record(:janitor)

      report = Health.report()
      assert report.checks.settlement.ok
      assert report.checks.janitor.ok
    end

    test "an overdue worker is degraded and says how late it is" do
      # Stamp settlement well past its 5-minute limit.
      :ets.insert(:heads_up_heartbeats, {:settlement, System.system_time(:second) - 3600})
      Heartbeat.record(:janitor)

      report = Health.report()

      refute report.checks.settlement.ok
      assert report.checks.settlement.last_run_seconds_ago >= 3600
      assert report.status == :degraded
    end

    test "the overall status is degraded when any single check fails" do
      :ets.insert(:heads_up_heartbeats, {:janitor, System.system_time(:second) - 10 * 3600})
      Heartbeat.record(:settlement)

      assert %{status: :degraded} = Health.report()
    end

    test "a blocked feed is reported as refused, not merely unreachable" do
      # This is the failure that ran silently for days: ESPN answering 403.
      :persistent_term.put({Health, :espn}, {System.monotonic_time(:millisecond), %{ok: false, detail: "refused with 403 — the feed is blocking this server"}})

      report = Health.report()

      refute report.checks.espn.ok
      assert report.checks.espn.detail =~ "403"
      assert report.status == :degraded
    end
  end
end
