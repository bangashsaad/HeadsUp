defmodule HeadsUp.Sports.BoxScore do
  @moduledoc """
  A single game's live/final box score from the ESPN summary feed, formatted like
  a normal box score (ESPN's own stat columns) plus one extra **fantasy** column
  per player, scored with the sport's default chart via `Settlement.Engine`.

  Basketball is one table per team; baseball is a batting + a pitching table.
  Fantasy is exact for basketball; for baseball's LIVE box score it's a close
  approximation (the in-game feed omits doubles/triples, so extra-base hits are
  counted as singles until the post-game log fills in).
  """
  alias HeadsUp.Sports.Espn.{Client, Parse}
  alias HeadsUp.Sports.Gamelog
  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Engine

  @doc "Box score for an ESPN event. `opts[:client]` injects a stub in tests."
  def for_event(sport, event_id, opts \\ []) do
    client = Keyword.get(opts, :client, Client)

    case client.summary(sport, event_id) do
      {:ok, body} -> {:ok, parse(sport, body)}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- parse --------------------------------------------------------------

  defp parse(sport, body) do
    status = get_in(body, ["header", "competitions", Access.at(0), "status", "type"]) || %{}
    comps = get_in(body, ["header", "competitions", Access.at(0), "competitors"]) || []
    meta = Map.new(comps, fn c -> {get_in(c, ["team", "abbreviation"]), c} end)

    teams =
      body
      |> get_in(["boxscore", "players"])
      |> List.wrap()
      |> Enum.map(&team(sport, &1, meta))
      # Away first, home second — the matchup hero renders left-to-right.
      |> Enum.sort_by(&(&1.home_away != "away"))

    %{
      event_id: to_string(get_in(body, ["header", "id"]) || ""),
      sport: sport,
      state: status["state"],
      status: status["shortDetail"] || status["description"] || "",
      teams: teams
    }
  end

  defp team(sport, t, meta) do
    abbrev = get_in(t, ["team", "abbreviation"])
    comp = Map.get(meta, abbrev, %{})

    %{
      abbrev: abbrev,
      name: get_in(t, ["team", "shortDisplayName"]) || get_in(t, ["team", "displayName"]),
      score: comp["score"],
      home_away: comp["homeAway"],
      logo: get_in(comp, ["team", "logo"]) || get_in(t, ["team", "logo"]),
      color: get_in(comp, ["team", "color"]),
      # Per-period scores (quarters / innings) for the matchup line-score strip.
      linescores:
        comp
        |> Map.get("linescores")
        |> List.wrap()
        |> Enum.map(&(&1["displayValue"] || to_string(&1["value"] || ""))),
      groups:
        t
        |> Map.get("statistics")
        |> List.wrap()
        |> Enum.filter(&scoreable_group?(sport, &1))
        |> Enum.map(&group(sport, &1))
    }
  end

  # ESPN ships ten football tables; six of them (defense, returns, kicking,
  # punting) cannot score a point under the @nfl chart, so they are dropped
  # rather than rendered as dead weight on a fantasy screen. Other sports keep
  # every table they publish.
  @nfl_groups ~w(passing rushing receiving fumbles)

  defp blank_to_nil(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: v)
  defp blank_to_nil(_), do: nil

  defp scoreable_group?("nfl", g), do: (g["name"] || "") in @nfl_groups
  defp scoreable_group?(_sport, _g), do: true

  defp group(sport, g) do
    labels = g["labels"] || []
    table = g["name"] || ""

    %{
      # Football tables carry their heading in "name" ("passing") while the
      # other sports use "type"; without the fallback every football table
      # would render unlabeled.
      type: blank_to_nil(g["type"]) || table,
      columns: labels,
      rows:
        g
        |> Map.get("athletes")
        |> List.wrap()
        |> Enum.map(&row(sport, labels, &1, table))
        |> Enum.reject(&is_nil/1)
    }
  end

  defp row(sport, labels, a, table) do
    name = get_in(a, ["athlete", "displayName"])
    stats = a["stats"] || []

    if name in [nil, ""] or stats == [] do
      nil
    else
      %{
        name: name,
        position: get_in(a, ["athlete", "position", "abbreviation"]),
        # Box-score rows come straight from ESPN, not our players table, so
        # they carry their own athlete id — enough to show a face here too.
        headshot_url: HeadsUp.Sports.Headshot.url(sport, to_string(get_in(a, ["athlete", "id"]) || "")),
        starter: a["starter"] == true,
        stats: stats,
        # The ESPN athlete id and the scoring categories behind `fantasy`.
        # Settlement re-joins on the id and sums the categories across tables,
        # so the box score you read and the duel score you're paid come from
        # one parse rather than two that can drift.
        external_id: to_string(get_in(a, ["athlete", "id"]) || ""),
        line: fantasy_line(sport, labels, stats, table),
        fantasy:
          Float.round(
            Engine.player_points(fantasy_line(sport, labels, stats, table), Scoring.default_rules(sport)) * 1.0,
            1
          )
      }
    end
  end

  # --- fantasy line from the box-score columns ----------------------------

  defp fantasy_line(sport, labels, stats, table) do
    case Gamelog.family(sport) do
      :basketball -> basketball_line(labels, stats)
      :baseball -> baseball_line(labels, stats)
      :football -> football_line(table, labels, stats)
      :other -> %{}
    end
  end

  # A football row's fantasy is the contribution of THAT table, because ESPN
  # lists a dual-threat player once per table. "YDS" and "TD" mean different
  # things in each, so the table name is what disambiguates them — reading by
  # label alone would score a rushing touchdown as a passing one.
  defp football_line(table, labels, stats) do
    g = fn l -> Parse.to_int(Parse.stat_value(labels, stats, l)) end

    case table do
      "passing" ->
        %{"passing_yards" => g.("YDS"), "passing_td" => g.("TD"), "interception" => g.("INT")}

      "rushing" ->
        %{"rushing_yards" => g.("YDS"), "rushing_td" => g.("TD")}

      "receiving" ->
        %{"reception" => g.("REC"), "receiving_yards" => g.("YDS"), "receiving_td" => g.("TD")}

      "fumbles" ->
        %{"fumble_lost" => g.("LOST")}

      _ ->
        %{}
    end
  end

  defp basketball_line(labels, stats) do
    g = fn l -> Parse.to_int(Parse.stat_value(labels, stats, l)) end

    %{
      "point" => g.("PTS"),
      "rebound" => g.("REB"),
      "assist" => g.("AST"),
      "steal" => g.("STL"),
      "block" => g.("BLK"),
      "turnover" => g.("TO"),
      "three_made" => Parse.made_from(Parse.stat_value(labels, stats, "3PT"))
    }
  end

  defp baseball_line(labels, stats) do
    g = fn l -> Parse.to_int(Parse.stat_value(labels, stats, l)) end

    if "IP" in labels do
      %{
        "inning_pitched" => innings(Parse.stat_value(labels, stats, "IP")),
        "strikeout_pitched" => g.("K"),
        "earned_run" => g.("ER"),
        "win" => 0
      }
    else
      h = g.("H")
      hr = g.("HR")

      %{
        # No 2B/3B in the live feed → extra-base hits count as singles (approx).
        "single" => max(h - hr, 0),
        "double" => 0,
        "triple" => 0,
        "home_run" => hr,
        "run" => g.("R"),
        "rbi" => g.("RBI"),
        "walk" => g.("BB"),
        "stolen_base" => g.("SB")
      }
    end
  end

  # Baseball innings notation "6.2" = 6⅔ (the decimal counts outs).
  defp innings(s) do
    case String.split(to_string(s), ".") do
      [whole] -> Parse.to_int(whole) * 1.0
      [whole, frac] -> Parse.to_int(whole) + min(Parse.to_int(frac), 2) / 3.0
      _ -> 0.0
    end
  end
end
