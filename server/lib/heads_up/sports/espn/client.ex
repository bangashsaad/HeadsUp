defmodule HeadsUp.Sports.Espn.Client do
  @moduledoc """
  Thin Req wrapper over the undocumented ESPN WNBA endpoints. Every function
  returns `{:ok, body_map}` or `{:error, reason}` and NEVER raises — callers
  decide how to degrade.

  Two ESPN hosts are used: the `site.api` host (scoreboard/summary/teams/roster,
  Phase 5b) and the `site.web.api` "common/v3" host (athlete gamelog + stats,
  Phase 7). Both base URLs + Req options come from one app-config namespace so
  tests can point them at a `Req.Test` plug:

      config :heads_up, HeadsUp.Sports.Espn,
        base_url: "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba",
        web_base_url: "https://site.web.api.espn.com/apis/common/v3/sports/basketball/wnba",
        req_options: []
  """

  @default_web_base "https://site.web.api.espn.com/apis/common/v3/sports/basketball/wnba"

  @doc "Games for one calendar day, `date` as `\"YYYYMMDD\"`."
  @spec scoreboard(String.t()) :: {:ok, map()} | {:error, term()}
  def scoreboard(date) when is_binary(date), do: get("/scoreboard", dates: date)

  @doc "Full game summary (incl. boxscore) for an ESPN event id."
  @spec summary(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def summary(event_id), do: get("/summary", event: to_string(event_id))

  @doc "All WNBA teams."
  @spec teams() :: {:ok, map()} | {:error, term()}
  def teams, do: get("/teams", [])

  @doc "One team's roster (athletes with id/name/position)."
  @spec roster(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def roster(team_id), do: get("/teams/#{team_id}/roster", [])

  @doc "An athlete's per-game log (labels + events + per-game stats)."
  @spec gamelog(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def gamelog(athlete_id), do: get_web("/athletes/#{athlete_id}/gamelog", [])

  @doc "An athlete's season splits (averages / totals categories)."
  @spec athlete_stats(String.t() | integer()) :: {:ok, map()} | {:error, term()}
  def athlete_stats(athlete_id), do: get_web("/athletes/#{athlete_id}/stats", [])

  # --- internals ----------------------------------------------------------

  defp get(path, params), do: request(base(:base_url) <> path, params)

  defp get_web(path, params), do: request(web_base() <> path, params)

  defp base(key) do
    Application.get_env(:heads_up, HeadsUp.Sports.Espn, []) |> Keyword.fetch!(key)
  end

  defp web_base do
    Application.get_env(:heads_up, HeadsUp.Sports.Espn, [])
    |> Keyword.get(:web_base_url, @default_web_base)
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

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end
end
