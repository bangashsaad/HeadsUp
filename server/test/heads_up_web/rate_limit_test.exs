defmodule HeadsUpWeb.RateLimitTest do
  @moduledoc "The limiter itself — the app disables it in test, so drive the plug directly."
  use HeadsUpWeb.ConnCase, async: false

  alias HeadsUpWeb.Plugs.RateLimit

  setup do
    RateLimit.init_table()
    Application.put_env(:heads_up, :rate_limiting_enabled, true)
    on_exit(fn -> Application.put_env(:heads_up, :rate_limiting_enabled, false) end)
    :ok
  end

  defp hit(bucket, opts \\ []) do
    limit = Keyword.get(opts, :limit, 3)
    ip = Keyword.get(opts, :ip, "203.0.113.7")

    build_conn()
    |> Plug.Conn.put_req_header("fly-client-ip", ip)
    |> RateLimit.call(RateLimit.init(limit: limit, window_ms: 60_000, key: bucket))
  end

  test "allows up to the limit, then answers 429 with retry-after" do
    bucket = "t_basic"
    for _ <- 1..3, do: refute(hit(bucket).halted)

    blocked = hit(bucket)
    assert blocked.halted
    assert blocked.status == 429
    assert [secs] = Plug.Conn.get_resp_header(blocked, "retry-after")
    assert secs == "60"
  end

  test "counts each client IP separately" do
    bucket = "t_perip"
    for _ <- 1..4, do: hit(bucket, ip: "198.51.100.1")

    # A different phone is unaffected by the noisy one.
    refute hit(bucket, ip: "198.51.100.2").halted
  end

  test "buckets don't bleed into each other" do
    for _ <- 1..4, do: hit("t_login")
    refute hit("t_register").halted
  end

  test "the master switch turns it off" do
    Application.put_env(:heads_up, :rate_limiting_enabled, false)
    for _ <- 1..20, do: refute(hit("t_off").halted)
  end

  test "fails OPEN if the table is missing — never locks real users out" do
    :ets.delete(:heads_up_rate_limit)
    refute hit("t_gone").halted
    RateLimit.init_table()
  end
end
