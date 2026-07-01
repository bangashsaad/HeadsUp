defmodule HeadsUp.Stats do
  @moduledoc """
  Read-only competitive stats derived from SETTLED duels + their results: a
  user's win/loss record and current streak, their head-to-head record vs each
  opponent, and a friends leaderboard. Pure aggregation — every figure comes from
  `duels` (winner_id / status) joined with `settlement_results` (the frozen team
  totals), reduced in Elixir into normalized per-duel "outcome rows".
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Accounts.User
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Settlement.Result
  alias HeadsUp.Social

  @doc "A user's overall record, points for/against, current streak, and recent form."
  def record_for(user_id) do
    {duels, results} = settled_with_results([user_id])
    duels |> rows_for(user_id, results) |> aggregate()
  end

  @doc "A user's record against each opponent they've faced, most-played first."
  def head_to_head(user_id) do
    {duels, results} = settled_with_results([user_id])

    duels
    |> rows_for(user_id, results)
    |> Enum.group_by(& &1.opponent.id)
    |> Enum.map(fn {_oid, rows} ->
      rows |> aggregate() |> Map.put(:opponent, hd(rows).opponent)
    end)
    |> Enum.sort_by(&{-&1.played, -&1.wins})
  end

  @doc """
  Standings among the user and their friends, ranked by wins then win %. Each
  person's record counts ALL their settled duels (not only ones vs the viewer).
  """
  def leaderboard(%User{} = user) do
    people = [user | Social.list_friends(user)] |> Enum.uniq_by(& &1.id)
    {duels, results} = settled_with_results(Enum.map(people, & &1.id))

    people
    |> Enum.map(fn u ->
      duels |> rows_for(u.id, results) |> aggregate() |> Map.put(:user, u)
    end)
    |> Enum.sort_by(&{-&1.wins, -&1.win_pct, &1.losses})
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

  # --- internals ----------------------------------------------------------

  defp settled_with_results(user_ids) do
    duels =
      from(d in Duel,
        where: d.status == "settled" and (d.challenger_id in ^user_ids or d.opponent_id in ^user_ids),
        preload: [:challenger, :opponent]
      )
      |> Repo.all()

    results =
      from(r in Result, where: r.duel_id in ^Enum.map(duels, & &1.id))
      |> Repo.all()
      |> Map.new(&{&1.duel_id, &1})

    {duels, results}
  end

  # Normalize each duel the user is in to one outcome row from THEIR perspective.
  defp rows_for(duels, user_id, results) do
    duels
    |> Enum.filter(&involves?(&1, user_id))
    |> Enum.map(fn d ->
      {pf, pa} = points(d, Map.get(results, d.id), user_id)

      %{
        outcome: outcome(d, user_id),
        pf: pf,
        pa: pa,
        opponent: opponent_user(d, user_id),
        settled_at: d.settled_at
      }
    end)
    |> Enum.sort_by(& &1.settled_at, {:desc, DateTime})
  end

  defp aggregate(rows) do
    wins = Enum.count(rows, &(&1.outcome == :win))
    losses = Enum.count(rows, &(&1.outcome == :loss))
    ties = Enum.count(rows, &(&1.outcome == :tie))
    decided = wins + losses

    %{
      wins: wins,
      losses: losses,
      ties: ties,
      played: wins + losses + ties,
      points_for: rows |> Enum.map(& &1.pf) |> Enum.sum() |> f1(),
      points_against: rows |> Enum.map(& &1.pa) |> Enum.sum() |> f1(),
      win_pct: if(decided > 0, do: Float.round(wins / decided, 3), else: 0.0),
      streak: streak(rows),
      recent: rows |> Enum.take(5) |> Enum.map(&letter(&1.outcome))
    }
  end

  # rows are sorted newest-first; the streak is the leading run of one outcome.
  defp streak([]), do: %{type: "none", count: 0}

  defp streak([%{outcome: type} | _] = rows) do
    count = rows |> Enum.take_while(&(&1.outcome == type)) |> length()
    %{type: to_string(type), count: count}
  end

  defp outcome(%Duel{winner_id: nil}, _user_id), do: :tie
  defp outcome(%Duel{winner_id: w}, user_id) when w == user_id, do: :win
  defp outcome(%Duel{}, _user_id), do: :loss

  defp points(_d, nil, _user_id), do: {0.0, 0.0}
  defp points(%Duel{challenger_id: c}, r, user_id) when c == user_id, do: {r.challenger_points, r.opponent_points}
  defp points(%Duel{}, r, _user_id), do: {r.opponent_points, r.challenger_points}

  defp involves?(%Duel{challenger_id: c, opponent_id: o}, id), do: c == id or o == id

  defp opponent_user(%Duel{challenger_id: c, challenger: ch, opponent: op}, id) do
    if c == id, do: op, else: ch
  end

  defp letter(:win), do: "W"
  defp letter(:loss), do: "L"
  defp letter(:tie), do: "T"

  defp f1(n), do: Float.round(n * 1.0, 1)
end
