defmodule HeadsUp.Sports.Seeds do
  @moduledoc """
  Placeholder player & game data so we can build and test the draft.
  Teams/rosters are approximate and will be REPLACED by the live stats
  provider later — accuracy here doesn't matter, only that the pool exists.
  """
  alias HeadsUp.Repo
  alias HeadsUp.Sports.{Player, Game}

  def run do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    seed_players(now)
    seed_games(now)
    :ok
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
