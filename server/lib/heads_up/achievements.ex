defmodule HeadsUp.Achievements do
  @moduledoc """
  Derived trophies for a user, computed on demand from their settled duels +
  results (no stored state). Each catalog entry is a threshold over one metric;
  `for_user/1` returns the full catalog with each trophy's current value and
  whether it's earned, so the UI can show progress toward the locked ones too.
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Contests.Duel
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
    %{key: "rivalry", title: "Rivalry", desc: "Face one opponent 5 times", icon: "people", metric: :max_vs_one, threshold: 5}
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

  defp load(user_id) do
    duels =
      from(d in Duel,
        where: d.status == "settled" and (d.challenger_id == ^user_id or d.opponent_id == ^user_id),
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
        is_ch = d.challenger_id == user_id
        r = Map.get(results, d.id)
        {pf, pa} = points(r, is_ch)

        %{
          won: d.winner_id == user_id,
          pf: pf,
          pa: pa,
          opp: if(is_ch, do: d.opponent_id, else: d.challenger_id),
          top: top_player(r, is_ch)
        }
      end)

    %{
      wins: Enum.count(rows, & &1.won),
      played: length(rows),
      best_streak: best_streak(rows),
      max_points: rows |> Enum.map(&round(&1.pf)) |> maxi(),
      max_margin: rows |> Enum.filter(& &1.won) |> Enum.map(&round(&1.pf - &1.pa)) |> maxi(),
      top_player: rows |> Enum.map(&round(&1.top)) |> maxi(),
      max_vs_one: rows |> Enum.frequencies_by(& &1.opp) |> Map.values() |> maxi()
    }
  end

  defp points(nil, _), do: {0.0, 0.0}
  defp points(r, true), do: {r.challenger_points, r.opponent_points}
  defp points(r, false), do: {r.opponent_points, r.challenger_points}

  defp top_player(nil, _), do: 0

  defp top_player(r, is_ch) do
    side = if is_ch, do: "challenger", else: "opponent"

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
