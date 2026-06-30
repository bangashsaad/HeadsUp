defmodule HeadsUp.Sports.Espn.Client do
  @moduledoc """
  Thin Req wrapper over the four undocumented ESPN `site.api.espn.com` WNBA
  endpoints used by Phase 5b. Every function returns `{:ok, body_map}` or
  `{:error, reason}` and NEVER raises — callers (the re-seed task, the live stats
  provider) decide how to degrade.

  Base URL and Req options come from one app-config namespace so tests can point
  it at a `Req.Test` plug:

      config :heads_up, HeadsUp.Sports.Espn,
        base_url: "https://site.api.espn.com/apis/site/v2/sports/basketball/wnba",
        req_options: []
  """

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

  # --- internals ----------------------------------------------------------

  defp get(path, params) do
    cfg = Application.get_env(:heads_up, HeadsUp.Sports.Espn, [])
    base = Keyword.fetch!(cfg, :base_url)
    opts = Keyword.get(cfg, :req_options, [])

    defaults = [
      url: base <> path,
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
