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
  alias HeadsUp.Contests.{Duel, Participant}
  alias HeadsUp.Settlement.Result
  alias HeadsUp.Social

  @doc "A user's overall record, points for/against, current streak, and recent form."
  def record_for(user_id) do
    {duels, results} = settled_with_results([user_id])
    duels |> rows_for(user_id, results) |> aggregate()
  end

  @doc """
  A user's record against each opponent they've faced, most-played first.
  Head-to-head is a 1v1 stat — group duels don't count toward any pairing.
  """
  def head_to_head(user_id) do
    {duels, results} = settled_with_results([user_id])

    duels
    |> rows_for(user_id, results)
    |> Enum.reject(&is_nil(&1.opponent))
    |> Enum.group_by(& &1.opponent.id)
    |> Enum.map(fn {_oid, rows} ->
      rows |> aggregate() |> Map.put(:opponent, hd(rows).opponent)
    end)
    |> Enum.sort_by(&{-&1.played, -&1.wins})
  end

  @doc """
  The settled duels these two have played against each other, newest first.
  Same row shape as the head-to-head aggregate, so the profile screen can show
  the receipts behind the record rather than just the tally.
  """
  def history_vs(user_id, opponent_id, limit \\ 5) do
    {duels, results} = settled_with_results([user_id])

    duels
    |> rows_for(user_id, results)
    |> Enum.filter(&(&1.opponent && &1.opponent.id == opponent_id))
    |> Enum.take(limit)
    |> Enum.map(fn row ->
      Map.take(row, [:outcome, :pf, :pa, :settled_at])
    end)
  end

  @doc """
  One line introducing a user you might friend: their record and most-played
  league, or "new here" when they haven't dueled. Shown under search results
  on both clients.
  """
  def blurb(user_id) do
    rec = record_for(user_id)

    if rec.played > 0 do
      "#{rec.wins}–#{rec.losses} · plays #{favorite_league(user_id)}"
    else
      "new here"
    end
  end

  defp favorite_league(user_id) do
    from(d in Duel,
      where: d.challenger_id == ^user_id or d.opponent_id == ^user_id,
      group_by: d.sport,
      order_by: [desc: count(d.id)],
      select: d.sport,
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> "nobody yet"
      sport -> String.upcase(sport)
    end
  end

  @doc """
  One rivalry, whole: the head-to-head tally plus the bragging-rights numbers
  (current run, average margin, best win) and the last duels as receipts, each
  with a one-line story derived from the frozen settlement breakdown — the top
  performer, the margin, a tie. Powers the phone's Rivalry page and the web
  profile's rivalry panel. 1v1 only, like every head-to-head stat.
  """
  def rivalry(user_id, opponent_id, history_limit \\ 5) do
    {duels, results} = settled_with_results([user_id])

    pair =
      duels
      |> Enum.filter(fn d ->
        {d.challenger_id, d.opponent_id} in [{user_id, opponent_id}, {opponent_id, user_id}]
      end)

    rows = rows_for(pair, user_id, results)
    agg = aggregate(rows)

    best_win =
      rows
      |> Enum.filter(&(&1.outcome == :win))
      |> Enum.map(&(&1.pf - &1.pa))
      |> Enum.max(fn -> nil end)

    history =
      pair
      |> Enum.sort_by(& &1.settled_at, {:desc, DateTime})
      |> Enum.take(history_limit)
      |> Enum.map(&history_entry(&1, Map.get(results, &1.id), user_id, rows))

    %{
      wins: agg.wins,
      losses: agg.losses,
      ties: agg.ties,
      played: agg.played,
      form: agg.recent,
      run: run_label(agg.streak),
      avg_margin: if(agg.played > 0, do: f1((agg.points_for - agg.points_against) / agg.played), else: nil),
      best_win: best_win && f1(best_win),
      history: history
    }
  end

  defp run_label(%{count: 0}), do: nil
  defp run_label(%{type: "win", count: c}), do: "W#{c}"
  defp run_label(%{type: "loss", count: c}), do: "L#{c}"
  defp run_label(%{type: "tie", count: c}), do: "T#{c}"
  defp run_label(_), do: nil

  defp history_entry(duel, result, user_id, all_rows) do
    {pf, pa} = points(duel, result, user_id)
    outcome = outcome(duel, result, user_id)

    %{
      outcome: outcome,
      my_points: f1(pf),
      their_points: f1(pa),
      settled_at: duel.settled_at,
      story: story(duel, result, user_id, outcome, pf, pa, all_rows)
    }
  end

  # --- the story generator ---------------------------------------------------
  # One line per receipt, written only from what the data can prove: ties,
  # series-best margins, blowouts, squeakers, and each side's top performer.

  defp story(_duel, _result, _user_id, :tie, _pf, _pa, _rows), do: "Dead heat — split the pot."

  defp story(duel, result, user_id, outcome, pf, pa, rows) do
    margin = abs(pf - pa)

    cond do
      outcome == :win and margin == series_best(rows, :win) and wins_in(rows) > 1 ->
        "Your biggest win of the series"

      outcome == :loss and margin == series_best(rows, :loss) and losses_in(rows) > 1 ->
        "Their biggest win of the series"

      margin >= 20.0 and outcome == :win ->
        "Never in doubt — up #{f1(margin)}"

      margin >= 20.0 ->
        "A beatdown — down #{f1(margin)}"

      margin <= 3.0 and outcome == :win ->
        "Escaped by #{f1(margin)}"

      margin <= 3.0 ->
        "Slipped away by #{f1(margin)}"

      true ->
        performer_story(duel, result, user_id, outcome) || margin_story(outcome, margin)
    end
  end

  defp series_best(rows, outcome) do
    rows
    |> Enum.filter(&(&1.outcome == outcome))
    |> Enum.map(&abs(&1.pf - &1.pa))
    |> Enum.max(fn -> nil end)
  end

  defp wins_in(rows), do: Enum.count(rows, &(&1.outcome == :win))
  defp losses_in(rows), do: Enum.count(rows, &(&1.outcome == :loss))

  defp performer_story(duel, result, user_id, outcome) do
    side = if outcome == :win, do: user_id, else: other_id(duel, user_id)

    case top_performer(duel, result, side) do
      %{"name" => name, "points" => pts} when is_binary(name) and is_number(pts) ->
        last = name |> String.split() |> List.last()

        cond do
          outcome == :win -> "#{last} #{f1(pts)} carried it"
          pts >= 30.0 -> "#{last} went nuclear (#{f1(pts)})"
          true -> "#{last} #{f1(pts)} did the damage"
        end

      _ ->
        nil
    end
  end

  defp margin_story(:win, margin), do: "Took it by #{f1(margin)}"
  defp margin_story(_, margin), do: "Dropped it by #{f1(margin)}"

  defp other_id(%Duel{challenger_id: c, opponent_id: o}, user_id),
    do: if(c == user_id, do: o, else: c)

  # The frozen per-player lines live in the result breakdown under the seat's
  # role key. Old or missing breakdowns just mean no performer line.
  defp top_performer(_duel, nil, _side), do: nil

  defp top_performer(%Duel{challenger_id: c}, %Result{breakdown: b}, side) when is_map(b) do
    key = if side == c, do: "challenger", else: "opponent"

    case get_in(b, [key, "players"]) do
      players when is_list(players) and players != [] ->
        Enum.max_by(players, &(&1["points"] || 0), fn -> nil end)

      _ ->
        nil
    end
  end

  defp top_performer(_duel, _result, _side), do: nil

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

  # A duel counts for a user if they hold a column (1v1) or an ACCEPTED seat
  # (group — declined invitees never played). distinct: two queried users in
  # the same group duel must not duplicate the row.
  defp settled_with_results(user_ids) do
    duels =
      from(d in Duel,
        left_join: p in Participant,
        on: p.duel_id == d.id and p.user_id in ^user_ids and p.status == "accepted",
        where:
          d.status == "settled" and
            (d.challenger_id in ^user_ids or d.opponent_id in ^user_ids or not is_nil(p.id)),
        distinct: true,
        preload: [:challenger, :opponent, participants: :user]
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
        outcome: outcome(d, Map.get(results, d.id), user_id),
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

  # Win = 1st place. In a group, a nil winner only means the TOP was shared —
  # it's a tie for those at rank 1 and a loss for everyone below them.
  defp outcome(%Duel{winner_id: w}, _r, user_id) when w == user_id, do: :win
  defp outcome(%Duel{opponent_id: nil} = d, r, user_id) do
    cond do
      not is_nil(d.winner_id) -> :loss
      my_rank(r, user_id) == 1 -> :tie
      true -> :loss
    end
  end

  defp outcome(%Duel{winner_id: nil}, _r, _user_id), do: :tie
  defp outcome(%Duel{}, _r, _user_id), do: :loss

  # Group points-against = the best OTHER total (the score you had to beat),
  # so win margins mean the same thing at any table size.
  defp points(_d, nil, _user_id), do: {0.0, 0.0}

  defp points(%Duel{opponent_id: nil}, r, user_id) do
    standings = standings(r)
    mine = Enum.find(standings, &(&1["user_id"] == user_id))
    best_other = standings |> Enum.reject(&(&1["user_id"] == user_id)) |> Enum.map(& &1["total"]) |> Enum.max(fn -> 0.0 end)
    {(mine && mine["total"]) || 0.0, best_other}
  end

  defp points(%Duel{challenger_id: c}, r, user_id) when c == user_id, do: {r.challenger_points, r.opponent_points}
  defp points(%Duel{}, r, _user_id), do: {r.opponent_points, r.challenger_points}

  defp standings(nil), do: []
  defp standings(%Result{breakdown: b}), do: (is_map(b) && b["standings"]) || []

  defp my_rank(r, user_id) do
    case Enum.find(standings(r), &(&1["user_id"] == user_id)) do
      %{"rank" => rank} -> rank
      _ -> nil
    end
  end

  defp involves?(%Duel{opponent_id: nil} = d, id),
    do: Enum.any?(d.participants, &(&1.user_id == id and &1.status == "accepted"))

  defp involves?(%Duel{challenger_id: c, opponent_id: o}, id), do: c == id or o == id

  # Group duels have no single opponent — H2H callers drop nil.
  defp opponent_user(%Duel{opponent_id: nil}, _id), do: nil

  defp opponent_user(%Duel{challenger_id: c, challenger: ch, opponent: op}, id) do
    if c == id, do: op, else: ch
  end

  defp letter(:win), do: "W"
  defp letter(:loss), do: "L"
  defp letter(:tie), do: "T"

  defp f1(n), do: Float.round(n * 1.0, 1)
end
