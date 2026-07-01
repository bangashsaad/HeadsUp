defmodule HeadsUp.Sports.Seeds do
  @moduledoc """
  Placeholder player & game data so we can build and test the draft.
  Teams/rosters are approximate and will be REPLACED by the live stats
  provider later — accuracy here doesn't matter, only that the pool exists.
  """
  import Ecto.Query, only: [from: 2]

  alias HeadsUp.Repo
  alias HeadsUp.Drafts.Pick
  alias HeadsUp.Sports.{Gamelog, Player, Game}
  alias HeadsUp.Sports.Espn.{Client, Parse}

  # Newly-discovered players (no game log yet) seed at a flat default projection
  # so they're draftable; the FPPG pass overwrites it for anyone with games.
  defp default_projection("wnba"), do: 40.0
  defp default_projection("mlb"), do: 5.0
  defp default_projection(_), do: 10.0

  def run do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    seed_players(now)
    seed_games(now)
    :ok
  end

  @doc """
  Re-seed the WNBA player pool from the live ESPN feed (Phase 5b). Pulls every
  team's roster and upserts players keyed FIRST by ESPN athlete id, then by
  normalized name — so existing rows keep their `id` and hand-ranked
  `projection` (drafted duels stay intact) while their `external_id` is migrated
  to the ESPN id the stats provider joins on. New players are inserted at the
  default projection. The whole thing runs in one transaction and aborts before
  any write if ANY ESPN fetch fails, so the pool is never left half-migrated.

  Idempotent: a second run matches the same rows by ESPN id and is a no-op.
  `opts[:client]` lets tests inject a stub implementing the `Client` API.

  Returns `{:ok, %{inserted: n, updated: m, total: t}}` or `{:error, reason}`.
  """
  def run_wnba_from_espn(opts \\ []), do: run_from_espn("wnba", opts)

  @doc """
  Generic version of `run_wnba_from_espn/1` for any sport with a live ESPN feed
  (WNBA, MLB, …). Same upsert/match semantics; position normalization is sport-
  specific (basketball coarsens to G/F/C, baseball keeps SP/RP/C/1B/…).
  """
  def run_from_espn(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)

    with {:ok, teams} <- fetch_teams(client, sport),
         {:ok, candidates} <- fetch_all_rosters(client, sport, teams) do
      upsert(sport, Enum.uniq_by(candidates, & &1.external_id))
    end
  end

  defp fetch_teams(client, sport) do
    case client.teams(sport) do
      {:ok, body} ->
        teams =
          body
          |> get_in(["sports", Access.at(0), "leagues", Access.at(0), "teams"])
          |> List.wrap()
          |> Enum.map(& &1["team"])
          |> Enum.reject(&is_nil/1)
          |> Enum.map(fn t -> %{id: t["id"], abbrev: t["abbreviation"]} end)
          |> Enum.reject(&is_nil(&1.id))

        if teams == [], do: {:error, :no_teams}, else: {:ok, teams}

      {:error, reason} ->
        {:error, {:teams, reason}}
    end
  end

  defp fetch_all_rosters(client, sport, teams) do
    Enum.reduce_while(teams, {:ok, []}, fn team, {:ok, acc} ->
      case client.roster(sport, team.id) do
        {:ok, body} ->
          abbrev = get_in(body, ["team", "abbreviation"]) || team.abbrev
          cands = body |> athletes_from() |> Enum.map(&candidate(&1, abbrev, sport)) |> Enum.reject(&is_nil/1)
          {:cont, {:ok, acc ++ cands}}

        {:error, reason} ->
          {:halt, {:error, {:roster, team.id, reason}}}
      end
    end)
  end

  @doc """
  Second seed pass: compute each player's season FPPG (fantasy points/game) from
  their ESPN game log and store it in `projection`, so the draft board ranks by
  real expected output instead of a hand-tuned number. Network-bound (one gamelog
  per player) but resilient — a player whose log can't be read or who has no games
  keeps their current projection. `opts[:client]` injects a stub in tests.

  Returns `{:ok, %{updated: n, total: t}}` (t = players with a numeric ESPN id).
  """
  def refresh_projections(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    numeric = Repo.all(from p in Player, where: p.sport == ^sport) |> Enum.filter(&numeric_id?/1)

    updates =
      numeric
      |> Task.async_stream(fn p -> {p.id, fppg(sport, p.external_id, client)} end,
        max_concurrency: 8,
        timeout: 30_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.flat_map(fn
        # Real game log → real FPPG. Reached but no games (DNP / no feed data) →
        # 0.0 so they sink below everyone who's actually produced, instead of
        # keeping a stale high rank. Fetch error → leave projection untouched.
        {:ok, {id, {:value, val}}} -> [{id, val}]
        {:ok, {id, :empty}} -> [{id, 0.0}]
        _ -> []
      end)

    Enum.each(updates, fn {id, val} ->
      from(p in Player, where: p.id == ^id) |> Repo.update_all(set: [projection: val])
    end)

    {:ok, %{updated: length(updates), total: length(numeric)}}
  end

  defp fppg(sport, external_id, client) do
    case client.gamelog(sport, external_id) do
      {:ok, body} ->
        case Gamelog.parse(sport, body) do
          [] -> :empty
          games -> {:value, Float.round(Enum.sum(Enum.map(games, & &1.fantasy)) / length(games), 1)}
        end

      {:error, _} ->
        :error
    end
  end

  defp numeric_id?(p), do: is_binary(p.external_id) and Regex.match?(~r/^\d+$/, p.external_id)

  @doc """
  Drop pre-ESPN placeholder rows for a sport: any player with a NON-numeric
  external_id (the name-slug ids the base `seeds.exs` made) that the ESPN reseed
  didn't migrate, EXCEPT any already used in a draft (the `:restrict` FK is the
  backstop). Keeps the live pool to real ESPN athletes only. Returns the count
  removed.
  """
  def prune_legacy(sport) do
    referenced = from(pk in Pick, select: pk.player_id)

    {count, _} =
      from(p in Player,
        where:
          p.sport == ^sport and fragment("? !~ '^[0-9]+$'", p.external_id) and
            p.id not in subquery(referenced)
      )
      |> Repo.delete_all()

    count
  end

  # ESPN rosters are usually a flat athlete list; tolerate the grouped
  # `[%{"items" => [...]}]` shape some endpoints return.
  defp athletes_from(body) do
    (body["athletes"] || [])
    |> Enum.flat_map(fn
      %{"items" => items} when is_list(items) -> items
      athlete when is_map(athlete) -> [athlete]
      _ -> []
    end)
  end

  defp candidate(athlete, abbrev, sport) do
    id = athlete["id"]
    name = athlete["displayName"] || athlete["fullName"]
    pos = get_in(athlete, ["position", "abbreviation"])

    if is_nil(id) or name in [nil, ""] do
      nil
    else
      %{
        sport: sport,
        external_id: to_string(id),
        name: name,
        team: abbrev,
        position: normalize_position(sport, pos)
      }
    end
  end

  # Basketball coarsens to G/F/C (the only positions the feed exposes); baseball
  # keeps the granular slot (SP/RP/C/1B/2B/3B/SS/OF/DH) the lineup templates need.
  defp normalize_position("mlb", pos), do: normalize_baseball_position(pos)
  defp normalize_position(_sport, pos), do: Parse.normalize_position(pos)

  defp normalize_baseball_position(pos) do
    p = (pos || "") |> to_string() |> String.downcase() |> String.trim()

    cond do
      p == "sp" or String.contains?(p, "starting") -> "SP"
      p in ~w(rp cp cl p) or String.contains?(p, "relief") or String.contains?(p, "pitch") -> "RP"
      p == "c" or String.contains?(p, "catch") -> "C"
      p == "1b" or String.contains?(p, "first") -> "1B"
      p == "2b" or String.contains?(p, "second") -> "2B"
      p == "3b" or String.contains?(p, "third") -> "3B"
      p == "ss" or String.contains?(p, "short") -> "SS"
      p == "dh" or String.contains?(p, "designated") -> "DH"
      p in ~w(of lf cf rf) or String.contains?(p, "field") -> "OF"
      # Unknown → OF: a UTIL-eligible hitter slot, so the player is never undraftable.
      true -> "OF"
    end
  end

  defp upsert(sport, candidates) do
    Repo.transaction(fn ->
      existing = Repo.all(from p in Player, where: p.sport == ^sport)
      by_eid = Map.new(existing, &{&1.external_id, &1})

      # Collision-aware name index: a normalized name shared by more than one
      # existing row is AMBIGUOUS and excluded, so a candidate can never update
      # the WRONG same-named player. (ESPN-id matching still works; a genuinely
      # new same-named athlete is inserted fresh rather than corrupting a row.)
      by_name =
        existing
        |> Enum.group_by(&Parse.normalize_name(&1.name))
        |> Enum.flat_map(fn
          {key, [only]} -> [{key, only}]
          {_key, _ambiguous} -> []
        end)
        |> Map.new()

      {ins, upd, _used} =
        Enum.reduce(candidates, {0, 0, MapSet.new()}, fn cand, {ins, upd, used} ->
          case find_match(cand, by_eid, by_name, used) do
            nil ->
              %Player{}
              |> Player.changeset(Map.put(cand, :projection, default_projection(sport)))
              |> Repo.insert!()

              {ins + 1, upd, used}

            %Player{} = match ->
              # Preserve id + projection; migrate external_id and refresh name/team/position.
              match
              |> Player.changeset(Map.take(cand, [:external_id, :name, :team, :position]))
              |> Repo.update!()

              {ins, upd + 1, MapSet.put(used, match.id)}
          end
        end)

      %{inserted: ins, updated: upd, total: ins + upd}
    end)
  end

  defp find_match(cand, by_eid, by_name, used) do
    eid = Map.get(by_eid, cand.external_id)
    named = Map.get(by_name, Parse.normalize_name(cand.name))

    cond do
      eid && not MapSet.member?(used, eid.id) -> eid
      named && not MapSet.member?(used, named.id) -> named
      true -> nil
    end
  end

  defp seed_players(now) do
    rows =
      players()
      |> Enum.map(fn p -> Map.merge(p, %{inserted_at: now, updated_at: now}) end)

    Repo.insert_all(Player, rows,
      on_conflict: {:replace, [:name, :team, :position, :projection, :updated_at]},
      conflict_target: [:sport, :external_id]
    )
  end

  # Each sport's list is already hand-ranked best-first; assign a descending
  # projection so the existing order becomes the draft board / auto-pick rank.
  defp rank(players) do
    players
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> Map.put(p, :projection, 100.0 - i) end)
  end

  defp seed_games(now) do
    rows =
      games()
      |> Enum.with_index()
      |> Enum.map(fn {g, i} ->
        Map.merge(g, %{
          # spread the games out over the coming days
          starts_at: DateTime.add(now, (i + 1) * 12 * 3600, :second),
          status: "scheduled",
          inserted_at: now,
          updated_at: now
        })
      end)

    Repo.insert_all(Game, rows,
      on_conflict: {:replace, [:home_team, :away_team, :starts_at, :updated_at]},
      conflict_target: [:sport, :external_id]
    )
  end

  # Build a player map, deriving a stable external_id slug from the name.
  defp p(sport, name, team, position) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    %{sport: sport, external_id: slug, name: name, team: team, position: position}
  end

  defp players do
    nfl =
      [
        {"Patrick Mahomes", "KC", "QB"},
        {"Josh Allen", "BUF", "QB"},
        {"Lamar Jackson", "BAL", "QB"},
        {"Jalen Hurts", "PHI", "QB"},
        {"Joe Burrow", "CIN", "QB"},
        {"C.J. Stroud", "HOU", "QB"},
        {"Jordan Love", "GB", "QB"},
        {"Dak Prescott", "DAL", "QB"},
        {"Christian McCaffrey", "SF", "RB"},
        {"Bijan Robinson", "ATL", "RB"},
        {"Saquon Barkley", "PHI", "RB"},
        {"Breece Hall", "NYJ", "RB"},
        {"Jahmyr Gibbs", "DET", "RB"},
        {"Jonathan Taylor", "IND", "RB"},
        {"Derrick Henry", "BAL", "RB"},
        {"De'Von Achane", "MIA", "RB"},
        {"Tyreek Hill", "MIA", "WR"},
        {"CeeDee Lamb", "DAL", "WR"},
        {"Justin Jefferson", "MIN", "WR"},
        {"Ja'Marr Chase", "CIN", "WR"},
        {"Amon-Ra St. Brown", "DET", "WR"},
        {"A.J. Brown", "PHI", "WR"},
        {"Puka Nacua", "LAR", "WR"},
        {"Garrett Wilson", "NYJ", "WR"},
        {"Travis Kelce", "KC", "TE"},
        {"Sam LaPorta", "DET", "TE"},
        {"Mark Andrews", "BAL", "TE"},
        {"Trey McBride", "ARI", "TE"},
        {"Harrison Butker", "KC", "K"},
        {"Brandon Aubrey", "DAL", "K"}
      ]
      |> Enum.map(fn {n, t, pos} -> p("nfl", n, t, pos) end)
      |> rank()

    nba =
      [
        {"Nikola Jokic", "DEN", "C"},
        {"Joel Embiid", "PHI", "C"},
        {"Victor Wembanyama", "SAS", "C"},
        {"Anthony Davis", "DAL", "C"},
        {"Giannis Antetokounmpo", "MIL", "PF"},
        {"Jayson Tatum", "BOS", "PF"},
        {"Kevin Durant", "PHX", "PF"},
        {"Paolo Banchero", "ORL", "PF"},
        {"LeBron James", "LAL", "SF"},
        {"Kawhi Leonard", "LAC", "SF"},
        {"Jimmy Butler", "GSW", "SF"},
        {"Jaylen Brown", "BOS", "SF"},
        {"Shai Gilgeous-Alexander", "OKC", "SG"},
        {"Devin Booker", "PHX", "SG"},
        {"Donovan Mitchell", "CLE", "SG"},
        {"Anthony Edwards", "MIN", "SG"},
        {"Luka Doncic", "LAL", "PG"},
        {"Stephen Curry", "GSW", "PG"},
        {"Damian Lillard", "MIL", "PG"},
        {"Tyrese Haliburton", "IND", "PG"},
        {"Ja Morant", "MEM", "PG"},
        {"Jalen Brunson", "NYK", "PG"},
        {"Trae Young", "ATL", "PG"},
        {"De'Aaron Fox", "SAS", "PG"}
      ]
      |> Enum.map(fn {n, t, pos} -> p("nba", n, t, pos) end)
      |> rank()

    mlb =
      [
        {"Gerrit Cole", "NYY", "SP"},
        {"Tarik Skubal", "DET", "SP"},
        {"Zack Wheeler", "PHI", "SP"},
        {"Paul Skenes", "PIT", "SP"},
        {"Corbin Burnes", "ARI", "SP"},
        {"Emmanuel Clase", "CLE", "RP"},
        {"Josh Hader", "HOU", "RP"},
        {"Adley Rutschman", "BAL", "C"},
        {"William Contreras", "MIL", "C"},
        {"Freddie Freeman", "LAD", "1B"},
        {"Vladimir Guerrero Jr.", "TOR", "1B"},
        {"Pete Alonso", "NYM", "1B"},
        {"Jose Altuve", "HOU", "2B"},
        {"Marcus Semien", "TEX", "2B"},
        {"Jose Ramirez", "CLE", "3B"},
        {"Rafael Devers", "BOS", "3B"},
        {"Manny Machado", "SD", "3B"},
        {"Bobby Witt Jr.", "KC", "SS"},
        {"Gunnar Henderson", "BAL", "SS"},
        {"Francisco Lindor", "NYM", "SS"},
        {"Aaron Judge", "NYY", "OF"},
        {"Mookie Betts", "LAD", "OF"},
        {"Juan Soto", "NYM", "OF"},
        {"Ronald Acuna Jr.", "ATL", "OF"},
        {"Kyle Tucker", "CHC", "OF"},
        {"Shohei Ohtani", "LAD", "DH"},
        {"Yordan Alvarez", "HOU", "DH"},
        # Extra RP + C so the small SHARED pool has margin for a 2-team draft
        # (mlb_standard/mlb_quick each demand 2 of these across both rosters).
        {"Edwin Diaz", "NYM", "RP"},
        {"Devin Williams", "NYY", "RP"},
        {"Will Smith", "LAD", "C"},
        {"Salvador Perez", "KC", "C"}
      ]
      |> Enum.map(fn {n, t, pos} -> p("mlb", n, t, pos) end)
      |> rank()

    # WNBA reuses NBA positions (PG/SG/SF/PF/C) and scoring; in active season
    # right now, so it's the sport to use for real end-to-end testing.
    wnba =
      [
        {"Caitlin Clark", "IND", "PG"},
        {"Sabrina Ionescu", "NY", "PG"},
        {"Chelsea Gray", "LV", "PG"},
        {"Courtney Vandersloot", "CHI", "PG"},
        {"Skylar Diggins", "SEA", "PG"},
        {"Kelsey Plum", "LA", "PG"},
        {"Jordin Canada", "ATL", "PG"},
        {"Natasha Cloud", "NY", "PG"},
        {"Jackie Young", "LV", "SG"},
        {"Arike Ogunbowale", "DAL", "SG"},
        {"Allisha Gray", "ATL", "SG"},
        {"Jewell Loyd", "LV", "SG"},
        {"Breanna Stewart", "NY", "SF"},
        {"Napheesa Collier", "MIN", "SF"},
        {"Kahleah Copper", "PHX", "SF"},
        {"Satou Sabally", "PHX", "SF"},
        {"Angel Reese", "CHI", "PF"},
        {"Alyssa Thomas", "PHX", "PF"},
        {"Nneka Ogwumike", "SEA", "PF"},
        {"Dearica Hamby", "LA", "PF"},
        {"A'ja Wilson", "LV", "C"},
        {"Jonquel Jones", "NY", "C"},
        {"Aliyah Boston", "IND", "C"},
        {"Brittney Griner", "ATL", "C"}
      ]
      |> Enum.map(fn {n, t, pos} -> p("wnba", n, t, pos) end)
      |> rank()

    nfl ++ nba ++ mlb ++ wnba
  end

  defp games do
    [
      g("nfl", "KC", "BAL"),
      g("nfl", "BUF", "MIA"),
      g("nfl", "PHI", "DAL"),
      g("nfl", "SF", "DET"),
      g("nba", "BOS", "NYK"),
      g("nba", "DEN", "LAL"),
      g("nba", "MIL", "PHI"),
      g("nba", "OKC", "DAL"),
      g("mlb", "LAD", "NYY"),
      g("mlb", "ATL", "PHI"),
      g("mlb", "HOU", "TEX"),
      g("mlb", "BAL", "CLE"),
      g("wnba", "LV", "NY"),
      g("wnba", "MIN", "IND"),
      g("wnba", "SEA", "PHX"),
      g("wnba", "ATL", "CHI")
    ]
  end

  defp g(sport, home, away) do
    %{
      sport: sport,
      external_id: "#{sport}-#{String.downcase(home)}-#{String.downcase(away)}",
      home_team: home,
      away_team: away
    }
  end
end
