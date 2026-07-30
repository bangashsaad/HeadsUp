defmodule HeadsUp.Sports.Gamelog do
  @moduledoc """
  Parses an ESPN athlete game-log body into a normalized per-game list, shared by
  everything that needs real per-game stats: the `Profile` (display), the seed's
  FPPG computation, and the MLB settlement provider. Keeping the parse in ONE
  place means a player's profile, their projection, and their duel score are all
  computed from byte-identical numbers.

  Each game is:

      %{
        event_id: "401815957",
        date: "2026-06-28T...",
        opponent: "PHI",
        home_away: "@",          # ESPN "atVs"
        result: "W",
        line: %{<engine category> => number},   # feeds Settlement.Engine
        box: %{...},             # sport-specific raw fields for display tiles
        display: "2-4 · 1 HR · 2 RBI",          # one-line box score for the UI
        fantasy: 14.0            # line scored under the sport's default chart
      }

  `line` keys are the SAME strings as `Contests.Scoring` charts, so
  `Settlement.Engine.player_points/2` scores them directly. Games are newest-first.

  Basketball (wnba/nba) reads the box-score by column LABEL (PTS/REB/…).
  Baseball (mlb) and football (nfl) read by the stable machine `names` array
  (atBats/homeRuns/…, passingYards/receptions/…). Baseball auto-detects a
  pitching vs batting log by the presence of `"innings"`; football reads every
  category it finds, because ESPN varies the columns by position (a QB log has
  passing+rushing, a receiver's has receiving+rushing+fumbles).
  """
  alias HeadsUp.Sports.Espn.Parse
  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Engine

  @doc "Family of a sport: `:basketball | :baseball | :other`."
  def family("wnba"), do: :basketball
  def family("nba"), do: :basketball
  def family("mlb"), do: :baseball
  def family("nfl"), do: :football
  def family(_), do: :other

  @doc "Normalized per-game list (newest first) parsed from an ESPN gamelog body."
  def parse(sport, body) when is_map(body) do
    rules = Scoring.default_rules(sport)
    labels = body["labels"] || []
    names = body["names"] || []
    meta = body["events"] || %{}

    stats_by_event =
      for st <- body["seasonTypes"] || [],
          cat <- st["categories"] || [],
          e <- cat["events"] || [],
          into: %{},
          do: {to_string(e["eventId"]), e["stats"] || []}

    meta
    |> Enum.map(fn {eid, m} -> {to_string(eid), m} end)
    |> Enum.filter(fn {eid, _m} -> Map.has_key?(stats_by_event, eid) end)
    |> Enum.map(fn {eid, m} -> game(sport, eid, m, Map.fetch!(stats_by_event, eid), labels, names, rules) end)
    |> Enum.sort_by(& &1.date, :desc)
  end

  def parse(_sport, _), do: []

  defp game(sport, eid, meta, stats, labels, names, rules) do
    {line, box, display} = read(family(sport), labels, names, stats)

    %{
      event_id: eid,
      date: meta["gameDate"],
      opponent: get_in(meta, ["opponent", "abbreviation"]) || get_in(meta, ["opponent", "displayName"]),
      home_away: meta["atVs"],
      result: meta["gameResult"],
      line: line,
      box: box,
      display: display,
      fantasy: Float.round(Engine.player_points(line, rules) * 1.0, 1)
    }
  end

  # --- basketball ---------------------------------------------------------

  defp read(:basketball, labels, _names, stats) do
    get = fn l -> Parse.to_int(Parse.stat_value(labels, stats, l)) end

    line = %{
      "point" => get.("PTS"),
      "rebound" => get.("REB"),
      "assist" => get.("AST"),
      "steal" => get.("STL"),
      "block" => get.("BLK"),
      "turnover" => get.("TO"),
      "three_made" => Parse.made_from(Parse.stat_value(labels, stats, "3PT"))
    }

    box = %{
      role: "B",
      minutes: get.("MIN"),
      points: line["point"],
      rebounds: line["rebound"],
      assists: line["assist"],
      steals: line["steal"],
      blocks: line["block"],
      turnovers: line["turnover"],
      three_made: line["three_made"],
      fg: Parse.stat_value(labels, stats, "FG"),
      three_pt: Parse.stat_value(labels, stats, "3PT"),
      ft: Parse.stat_value(labels, stats, "FT")
    }

    display = "#{line["point"]} PTS · #{line["rebound"]} REB · #{line["assist"]} AST"
    {line, box, display}
  end

  # --- baseball -----------------------------------------------------------

  defp read(:baseball, _labels, names, stats) do
    raw = fn key ->
      case Enum.find_index(names, &(&1 == key)) do
        nil -> nil
        i -> Enum.at(stats, i)
      end
    end

    geti = fn key -> Parse.to_int(raw.(key)) end

    if "innings" in names do
      pitching(raw, geti)
    else
      batting(geti)
    end
  end

  # --- football -----------------------------------------------------------

  # ESPN ships a DIFFERENT column set per position — a QB log has passing and
  # rushing, a receiver's has receiving, rushing and fumbles. Rather than
  # branching on role, read every category by name and let the missing ones
  # come back 0 (`Parse.to_int(nil)` == 0). The role is then inferred from what
  # actually has volume, which is only used to pick a display line.
  #
  # Known feed gap: ESPN omits fumbles from the QB column set, so a quarterback
  # never loses points for one. Both sides of a duel are scored identically, so
  # this cannot favor a player — it just makes QBs marginally cheap.
  defp read(:football, _labels, names, stats) do
    geti = fn key ->
      case Enum.find_index(names, &(&1 == key)) do
        nil -> 0
        i -> Parse.to_int(Enum.at(stats, i))
      end
    end

    pass_yds = geti.("passingYards")
    pass_td = geti.("passingTouchdowns")
    ints = geti.("interceptions")
    rush_yds = geti.("rushingYards")
    rush_td = geti.("rushingTouchdowns")
    rec = geti.("receptions")
    rec_yds = geti.("receivingYards")
    rec_td = geti.("receivingTouchdowns")

    line = %{
      "passing_yards" => pass_yds,
      "passing_td" => pass_td,
      "interception" => ints,
      "rushing_yards" => rush_yds,
      "rushing_td" => rush_td,
      "reception" => rec,
      "receiving_yards" => rec_yds,
      "receiving_td" => rec_td,
      "fumble_lost" => geti.("fumblesLost")
    }

    passer? = "passingYards" in names

    box = %{
      role: if(passer?, do: "QB", else: "SKILL"),
      completions: geti.("completions"),
      attempts: geti.("passingAttempts"),
      passing_yards: pass_yds,
      passing_td: pass_td,
      interceptions: ints,
      carries: geti.("rushingAttempts"),
      rushing_yards: rush_yds,
      rushing_td: rush_td,
      receptions: rec,
      targets: geti.("receivingTargets"),
      receiving_yards: rec_yds,
      receiving_td: rec_td,
      fumbles_lost: geti.("fumblesLost")
    }

    {line, box, football_display(passer?, box)}
  end

  # A stat line reads best when it leads with what the player actually did, so
  # show the passing line for a quarterback and the touches line for everyone
  # else, appending the secondary contribution only when it happened.
  defp football_display(true, box) do
    base = "#{box.completions}/#{box.attempts} · #{box.passing_yards} YDS · #{box.passing_td} TD"
    extras = football_extras([{box.interceptions, "INT"}, {box.rushing_td, "RUSH TD"}])
    Enum.join([base | extras], " · ")
  end

  defp football_display(false, box) do
    base =
      cond do
        box.receptions > 0 -> "#{box.receptions} REC · #{box.receiving_yards} YDS"
        box.carries > 0 -> "#{box.carries} CAR · #{box.rushing_yards} YDS"
        true -> "0 YDS"
      end

    tds = box.rushing_td + box.receiving_td

    extras =
      football_extras([{tds, "TD"}]) ++
        if(box.receptions > 0 and box.carries > 0, do: ["#{box.carries} CAR · #{box.rushing_yards} YDS"], else: [])

    Enum.join([base | extras], " · ")
  end

  defp football_extras(pairs) do
    pairs
    |> Enum.filter(fn {n, _} -> n > 0 end)
    |> Enum.map(fn {n, lbl} -> "#{n} #{lbl}" end)
  end

  defp read(:other, _labels, _names, _stats), do: {%{}, %{role: "?"}, ""}

  defp batting(geti) do
    ab = geti.("atBats")
    h = geti.("hits")
    d = geti.("doubles")
    t = geti.("triples")
    hr = geti.("homeRuns")
    single = max(h - d - t - hr, 0)
    r = geti.("runs")
    rbi = geti.("RBIs")
    bb = geti.("walks")
    sb = geti.("stolenBases")

    line = %{
      "single" => single,
      "double" => d,
      "triple" => t,
      "home_run" => hr,
      "run" => r,
      "rbi" => rbi,
      "walk" => bb,
      "stolen_base" => sb
    }

    box = %{role: "B", ab: ab, h: h, hr: hr, rbi: rbi, runs: r, sb: sb, bb: bb, doubles: d, triples: t}

    extras =
      [{hr, "HR"}, {rbi, "RBI"}, {sb, "SB"}, {bb, "BB"}]
      |> Enum.filter(fn {n, _} -> n > 0 end)
      |> Enum.map(fn {n, lbl} -> "#{n} #{lbl}" end)

    display = ["#{h}-#{ab}" | extras] |> Enum.join(" · ")
    {line, box, display}
  end

  defp pitching(raw, geti) do
    ip_raw = raw.("innings") || "0"
    ip = innings_to_float(ip_raw)
    k = geti.("strikeouts")
    er = geti.("earnedRuns")
    h = geti.("hits")
    bb = geti.("walks")
    dec = to_string(raw.("wins-losses") || "")
    win = if String.starts_with?(dec, "W"), do: 1, else: 0

    line = %{
      "inning_pitched" => ip,
      "strikeout_pitched" => k,
      "earned_run" => er,
      "win" => win
    }

    box = %{role: "P", ip: ip_raw, outs: round(ip * 3), k: k, er: er, hits: h, walks: bb, win: win}
    display = "#{ip_raw} IP · #{k} K · #{er} ER"
    {line, box, display}
  end

  # Baseball innings notation: the decimal counts OUTS, not tenths. "6.2" = 6⅔.
  defp innings_to_float(s) do
    case String.split(to_string(s), ".") do
      [whole] -> Parse.to_int(whole) * 1.0
      [whole, frac] -> Parse.to_int(whole) + min(Parse.to_int(frac), 2) / 3.0
      _ -> 0.0
    end
  end
end
