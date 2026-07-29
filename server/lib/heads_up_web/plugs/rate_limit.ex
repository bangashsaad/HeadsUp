defmodule HeadsUpWeb.Plugs.RateLimit do
  @moduledoc """
  A small fixed-window rate limiter, in ETS. No dependency and no Redis: the
  app runs on exactly ONE Fly machine (in-memory draft GenServers require it),
  so a node-local counter IS the global counter.

  Used to blunt the obvious abuse once signup is public — credential stuffing
  on login, mass account creation, and password-reset email floods.

      plug HeadsUpWeb.Plugs.RateLimit, limit: 5, window_ms: 60_000, key: "login"

  Keyed by client IP + the given bucket name. Over the limit answers 429 with
  a `retry-after` header and halts. Fails OPEN: any internal error lets the
  request through rather than locking real users out.
  """
  import Plug.Conn

  require Logger

  @table :heads_up_rate_limit

  @doc "Creates the ETS table. Called once at boot from the Application tree."
  def init_table do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    :ok
  rescue
    ArgumentError -> :ok
  end

  def init(opts) do
    %{
      limit: Keyword.fetch!(opts, :limit),
      window_ms: Keyword.fetch!(opts, :window_ms),
      bucket: Keyword.fetch!(opts, :key)
    }
  end

  def call(conn, %{limit: limit, window_ms: window_ms, bucket: bucket}) do
    if Application.get_env(:heads_up, :rate_limiting_enabled, true) do
      window = div(System.system_time(:millisecond), window_ms)
      key = {bucket, client_ip(conn), window}

      case bump(key, window_ms) do
        count when count > limit ->
          conn
          |> put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
          |> put_status(:too_many_requests)
          |> Phoenix.Controller.json(%{error: "Too many attempts — wait a moment and try again."})
          |> halt()

        _ ->
          conn
      end
    else
      conn
    end
  end

  # Atomic increment; the counter self-expires because the window number is
  # part of the key, and stale rows are swept opportunistically.
  defp bump(key, window_ms) do
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})
    if rem(count, 500) == 0, do: sweep(window_ms)
    count
  rescue
    # Table missing (or any ETS surprise) must never block a real request.
    _ ->
      Logger.warning("rate limiter unavailable — allowing request")
      0
  end

  defp sweep(window_ms) do
    current = div(System.system_time(:millisecond), window_ms)
    :ets.select_delete(@table, [{{{:_, :_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
  end

  # Behind Fly's proxy the real client is the first fly-client-ip / forwarded
  # entry; fall back to the socket address for local + test traffic.
  defp client_ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] when is_binary(ip) and ip != "" ->
        ip

      _ ->
        case get_req_header(conn, "x-forwarded-for") do
          [chain | _] when is_binary(chain) ->
            chain |> String.split(",") |> List.first() |> String.trim()

          _ ->
            conn.remote_ip |> :inet.ntoa() |> to_string()
        end
    end
  end
end
