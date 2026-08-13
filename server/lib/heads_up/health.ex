defmodule HeadsUp.Health do
  @moduledoc """
  Is this node actually doing its job? Not "did the web server answer" — it
  always answers — but "is the database reachable, is the sports feed letting
  us in, and have the background workers run recently".

  This exists because two failures ran for days without a single error line.
  ESPN began refusing the server with 403 and every caller failed open, so the
  app kept serving duels while quietly not filtering slates. The stale-duel
  janitor never fired at all. Nothing crashed, so nothing was noticed.

  `report/0` answers `%{status: :ok | :degraded, checks: %{...}}`. The endpoint
  returns 503 when degraded so the keepalive cron — which already pings this
  machine every 20 minutes — fails its own workflow and mails us.

  Workers stamp `Heartbeat.record/1` each pass. On a scale-to-zero machine a
  fresh boot has no stamps yet, so a worker is judged healthy while the node is
  still inside its grace period; otherwise every wake would report degraded.
  """

  alias HeadsUp.{Heartbeat, Repo}

  # A worker is late once it has missed several turns, not one.
  @settlement_max_age_s 5 * 60
  @janitor_max_age_s 2 * 60 * 60

  # Long enough for the first sweep of each worker to land after a cold boot.
  @boot_grace_s 120

  # The ESPN probe is cached so a tight ping loop can't hammer the feed.
  @espn_cache_ms 60_000
  @espn_key {__MODULE__, :espn}

  def report do
    checks = %{
      database: database(),
      espn: espn(),
      settlement: worker(:settlement, @settlement_max_age_s),
      janitor: worker(:janitor, @janitor_max_age_s)
    }

    status = if Enum.all?(checks, fn {_name, c} -> c.ok end), do: :ok, else: :degraded
    %{status: status, checks: checks}
  end

  defp database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> %{ok: true}
      {:error, reason} -> %{ok: false, detail: "unreachable: #{inspect(reason)}"}
    end
  end

  # A real call, because the failure mode we care about (being refused) is
  # invisible from inside the process. Cached for a minute so pinging health
  # can't itself become the thing that gets us rate-limited.
  defp espn do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@espn_key, nil) do
      {ts, result} when now - ts < @espn_cache_ms ->
        result

      _ ->
        result = probe_espn()
        :persistent_term.put(@espn_key, {now, result})
        result
    end
  end

  defp probe_espn do
    date = DateTime.utc_now() |> DateTime.to_date() |> Calendar.strftime("%Y%m%d")

    case HeadsUp.Sports.Espn.Client.scoreboard("wnba", date) do
      {:ok, _} ->
        %{ok: true}

      {:error, {:http, status}} when status in [401, 403] ->
        %{ok: false, detail: "refused with #{status} — the feed is blocking this server"}

      {:error, reason} ->
        %{ok: false, detail: "unreachable: #{inspect(reason)}"}
    end
  end

  defp worker(name, max_age_s) do
    uptime_s = div(elem(:erlang.statistics(:wall_clock), 0), 1000)

    case Heartbeat.age_seconds(name) do
      nil when uptime_s < @boot_grace_s ->
        %{ok: true, detail: "starting up"}

      nil ->
        %{ok: false, detail: "has not run since boot (#{uptime_s}s ago)"}

      age when age <= max_age_s ->
        %{ok: true, last_run_seconds_ago: age}

      age ->
        %{ok: false, last_run_seconds_ago: age, detail: "overdue (limit #{max_age_s}s)"}
    end
  end
end
