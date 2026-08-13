defmodule HeadsUp.Sports.Espn.Client do
  @moduledoc """
  Thin Req wrapper over the undocumented ESPN endpoints, league-aware: every
  call takes the `sport` ("wnba" | "nba" | "mlb" | "nfl") as its first argument
  and is routed to that league's path. Functions return `{:ok, body_map}` or
  `{:error, reason}` and NEVER raise on a transport/HTTP failure — callers decide
  how to degrade. (An unknown sport DOES raise, since it's a programmer error.)

  Both host roots + Req options come from one app-config namespace so tests can
  point them at a `Req.Test` plug:

      config :heads_up, HeadsUp.Sports.Espn,
        site_host: "https://site.web.api.espn.com/apis/site/v2/sports",
        web_host: "https://site.web.api.espn.com/apis/common/v3/sports",
        req_options: []

  Both roots live on `site.web.api.espn.com`. The `site/v2` paths
  (scoreboard/summary/teams/roster) were originally read from `site.api.espn.com`,
  which began answering this app's server with 403 while still serving the same
  paths to other clients — an IP-level block, unaffected by request headers.
  `site.web.api.espn.com` serves those paths byte-identically and is the host
  ESPN's own web app uses, so everything now goes through it.

  The host root is joined with the per-sport league path (e.g. `baseball/mlb`)
  to form the base URL, so adding a sport is one entry in `@leagues`.
  """

  @default_site_host "https://site.web.api.espn.com/apis/site/v2/sports"
  @default_web_host "https://site.web.api.espn.com/apis/common/v3/sports"
  # Same paths, different host — the fallback when one is refusing us.
  @mirror_site_host "https://site.api.espn.com/apis/site/v2/sports"

  # ESPN league path segment per sport (host_root <> "/" <> league <> path).
  @leagues %{
    "wnba" => "basketball/wnba",
    "nba" => "basketball/nba",
    "mlb" => "baseball/mlb",
    "nfl" => "football/nfl"
  }

  @doc "Sports with a live ESPN league mapping."
  @spec leagues() :: [String.t()]
  def leagues, do: Map.keys(@leagues)

  @doc "True if `sport` has an ESPN league mapping (a live feed)."
  @spec supported?(String.t()) :: boolean()
  def supported?(sport), do: Map.has_key?(@leagues, sport)

  @doc """
  Games for a calendar day (`"YYYYMMDD"`) or range (`"YYYYMMDD-YYYYMMDD"`).
  ESPN silently caps responses at 100 events — range callers that can exceed
  that (a full MLB week is ~105 games) must pass `limit:` in `extra`.
  """
  @spec scoreboard(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def scoreboard(sport, date, extra \\ []) when is_binary(date),
    do: get(sport, "/scoreboard", Keyword.merge([dates: date], extra))

  @doc "Full game summary (incl. boxscore) for an ESPN event id."
  @spec summary(String.t(), String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def summary(sport, event_id), do: get(sport, "/summary", event: to_string(event_id))

  @doc "League-wide injury report (per-team lists of athlete statuses)."
  @spec injuries(String.t()) :: {:ok, map()} | {:error, term()}
  def injuries(sport), do: get(sport, "/injuries", [])

  @doc "All teams in the league."
  @spec teams(String.t()) :: {:ok, map()} | {:error, term()}
  def teams(sport), do: get(sport, "/teams", [])

  @doc "One team's roster (athletes with id/name/position)."
  @spec roster(String.t(), String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def roster(sport, team_id), do: get(sport, "/teams/#{team_id}/roster", [])

  @doc "An athlete's per-game log (labels + events + per-game stats)."
  @spec gamelog(String.t(), String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def gamelog(sport, athlete_id), do: get_web(sport, "/athletes/#{athlete_id}/gamelog", [])

  @doc "An athlete's season splits (averages / totals categories)."
  @spec athlete_stats(String.t(), String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def athlete_stats(sport, athlete_id), do: get_web(sport, "/athletes/#{athlete_id}/stats", [])

  # --- internals ----------------------------------------------------------

  # Site paths are tried on the primary host, then the mirror. ESPN blocked one
  # host at the IP level while serving the identical paths from the other, and
  # the app degraded for days before anyone noticed; a second try costs nothing
  # on the happy path and turns that outage into a blip.
  defp get(sport, path, params) do
    case request(site_base(sport) <> path, params) do
      {:error, {:http, status}} = err when status in [401, 403] ->
        case alt_site_base(sport) do
          nil -> err
          base -> request(base <> path, params)
        end

      other ->
        other
    end
  end

  defp get_web(sport, path, params), do: request(web_base(sport) <> path, params)

  defp site_base(sport), do: host(:site_host, @default_site_host) <> "/" <> league!(sport)

  # The other host serving the same /apis/site/v2 paths. nil when the primary
  # has been overridden (tests point it at a stub, which must not fall back to
  # the real internet).
  defp alt_site_base(sport) do
    primary = host(:site_host, @default_site_host)

    cond do
      primary == @default_site_host -> @mirror_site_host <> "/" <> league!(sport)
      primary == @mirror_site_host -> @default_site_host <> "/" <> league!(sport)
      true -> nil
    end
  end

  defp web_base(sport), do: host(:web_host, @default_web_host) <> "/" <> league!(sport)

  defp league!(sport) do
    Map.get(@leagues, sport) ||
      raise ArgumentError, "no ESPN league mapping for sport #{inspect(sport)}"
  end

  defp host(key, default) do
    Application.get_env(:heads_up, HeadsUp.Sports.Espn, []) |> Keyword.get(key, default)
  end

  defp request(url, params) do
    opts = Application.get_env(:heads_up, HeadsUp.Sports.Espn, []) |> Keyword.get(:req_options, [])

    defaults = [
      url: url,
      params: params,
      receive_timeout: 8_000,
      retry: :transient,
      max_retries: 2,
      headers: [{"user-agent", "heads-up/1.0 (+settlement)"}]
    ]

    req = Req.new(Keyword.merge(defaults, opts))

    case Req.get(req) do
      {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
        if is_map(body), do: {:ok, body}, else: {:error, {:bad_body, body}}

      # 401/403 means ESPN is refusing this caller, not that the data is
      # missing — every caller fails OPEN, so without a log the app just
      # quietly stops filtering slates and nobody finds out.
      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        require Logger
        Logger.warning("ESPN refused #{url} with #{status} — feed degraded, callers will fail open")
        {:error, {:http, status}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end
end
