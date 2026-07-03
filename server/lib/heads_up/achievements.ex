defmodule HeadsUp.Achievements do
  @moduledoc """
  Derived trophies for a user, computed on demand from their settled duels +
  results (no stored state). Each catalog entry is a threshold over one metric;
  `for_user/1` returns the full catalog with each trophy's current value and
  whether it's earned, so the UI can show progress toward the locked ones too.
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Contests.{Duel, Participant}
  alias HeadsUp.Settlement.Result

  # icon = Ionicons name (mobile).
  @catalog [
    %{key: "first_win", title: "First Win", desc: "Win your first duel", icon: "trophy", metric: :wins, threshold: 1},
    %{key: "hat_trick", title: "Hat Trick", desc: "Win 3 duels in a row", icon: "flame", metric: :best_streak, threshold: 3},
    %{key: "on_fire", title: "On Fire", desc: "Win 5 duels in a row", icon: "bonfire", metric: :best_streak, threshold: 5},
    %{key: "veteran", title: "Veteran", desc: "Play 10 duels", icon: "shield-checkmark", metric: :played, threshold: 10},
    %{key: "century", title: "Century", desc: "Score 100+ in a single duel", icon: "ribbon", metric: :max_points, threshold: 100},
    %{key: "sharpshooter", title: "Sharpshooter", desc: "Draft a 50-point player", icon: "star", metric: :top_player, threshold: 50},
    %{key: "blowout", title: "Blowout", desc: "Win a duel by 30+", icon: "flash", metric: :max_margin, threshold: 30},
    %{key: "rivalry", title: "Rivalry", desc: "Face one opponent 5 times", icon: "people", metric: :max_vs_one, threshold: 5},
    %{key: "party_crasher", title: "Party Crasher", desc: "Win a group duel (3+ players)", icon: "medal", metric: :group_wins, threshold: 1}
  ]

  @doc "The full trophy catalog for `user_id`, each with its current value + earned flag."
  def for_user(user_id) do
    metrics = user_id |> load() |> metrics(user_id)

    Enum.map(@catalog, fn a ->
      value = Map.get(metrics, a.metric, 0)

      %{
        key: a.key,
        title: a.title,
        description: a.desc,
        icon: a.icon,
        threshold: a.threshold,
        value: value,
        earned: value >= a.threshold
      }
    end)
  end

  # Every settled contest the user PLAYED: a 1v1 column or an accepted seat.
  defp load(user_id) do
    duels =
      from(d in Duel,
        left_join: p in Participant,
        on: p.duel_id == d.id and p.user_id == ^user_id and p.status == "accepted",
        where:
          d.status == "settled" and
            (d.challenger_id == ^user_id or d.opponent_id == ^user_id or not is_nil(p.id)),
        distinct: true,
        order_by: [asc: d.settled_at]
      )
      |> Repo.all()

    results =
      from(r in Result, where: r.duel_id in ^Enum.map(duels, & &1.id))
      |> Repo.all()
      |> Map.new(&{&1.duel_id, &1})

    {duels, results}
  end

  defp metrics({duels, results}, user_id) do
    rows =
      Enum.map(duels, fn d ->
        group = is_nil(d.opponent_id)
        r = Map.get(results, d.id)
        {pf, pa} = points(d, r, user_id)

        %{
          won: d.winner_id == user_id,
          group: group,
          pf: pf,
          pa: pa,
          # Rivalry is a 1v1 stat — group rows carry no opponent.
          opp: if(group, do: nil, else: if(d.challenger_id == user_id, do: d.opponent_id, else: d.challenger_id)),
          top: top_player(d, r, user_id)
        }
      end)

    %{
      wins: Enum.count(rows, & &1.won),
      played: length(rows),
      best_streak: best_streak(rows),
      max_points: rows |> Enum.map(&round(&1.pf)) |> maxi(),
      max_margin: rows |> Enum.filter(& &1.won) |> Enum.map(&round(&1.pf - &1.pa)) |> maxi(),
      top_player: rows |> Enum.map(&round(&1.top)) |> maxi(),
      max_vs_one: rows |> Enum.reject(&is_nil(&1.opp)) |> Enum.frequencies_by(& &1.opp) |> Map.values() |> maxi(),
      group_wins: Enum.count(rows, &(&1.group and &1.won))
    }
  end

  # Group: my total vs the best OTHER total (win margin = gap to 2nd place).
  defp points(_d, nil, _user_id), do: {0.0, 0.0}

  defp points(%Duel{opponent_id: nil}, r, user_id) do
    standings = standings(r)
    mine = Enum.find(standings, &(&1["user_id"] == user_id))
    best_other = standings |> Enum.reject(&(&1["user_id"] == user_id)) |> Enum.map(& &1["total"]) |> Enum.max(fn -> 0.0 end)
    {(mine && mine["total"]) || 0.0, best_other}
  end

  defp points(%Duel{challenger_id: c}, r, user_id) when c == user_id, do: {r.challenger_points, r.opponent_points}
  defp points(%Duel{}, r, _user_id), do: {r.opponent_points, r.challenger_points}

  defp standings(%Result{breakdown: b}), do: (is_map(b) && b["standings"]) || []

  defp top_player(_d, nil, _user_id), do: 0

  defp top_player(%Duel{opponent_id: nil}, r, user_id) do
    case Enum.find(standings(r), &(&1["user_id"] == user_id)) do
      %{"players" => players} -> players |> Enum.map(&(&1["points"] || 0)) |> maxi()
      _ -> 0
    end
  end

  defp top_player(%Duel{challenger_id: c}, r, user_id) do
    side = if c == user_id, do: "challenger", else: "opponent"

    (get_in(r.breakdown, [side, "players"]) || [])
    |> Enum.map(&(&1["points"] || 0))
    |> maxi()
  end

  defp best_streak(rows) do
    rows
    |> Enum.reduce({0, 0}, fn r, {cur, best} ->
      cur = if r.won, do: cur + 1, else: 0
      {cur, max(best, cur)}
    end)
    |> elem(1)
  end

  # Max of a non-negative list, 0 for empty.
  defp maxi(list), do: Enum.max([0 | list])
end
