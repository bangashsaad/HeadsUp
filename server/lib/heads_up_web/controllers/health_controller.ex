defmodule HeadsUpWeb.HealthController do
  @moduledoc """
  GET /api/health — a dependency check, not a liveness ping.

  Answers 200 when the database, the sports feed and both background workers
  are healthy, and 503 when any of them is not. The 503 is the point: the
  keepalive workflow already curls this machine every 20 minutes with
  `--fail`, so a degraded node fails that workflow and GitHub mails us. That
  is the whole alerting system, and it costs nothing extra to run.

  Unauthenticated (a cron can't log in) and deliberately free of anything
  sensitive — it reports whether dependencies answer, never what they said.
  """
  use HeadsUpWeb, :controller

  def index(conn, _params) do
    report = HeadsUp.Health.report()
    status = if report.status == :ok, do: 200, else: 503

    conn
    |> put_status(status)
    |> json(%{status: report.status, checks: report.checks})
  end
end
