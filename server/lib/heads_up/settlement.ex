defmodule HeadsUp.Settlement do
  @moduledoc """
  The Settlement context: closes the duel loop. For a "drafted" duel whose
  scoring window has elapsed, it loads both rosters from the draft, fetches each
  player's stat line from the configured (swappable) stats provider, scores them
  against the duel's FROZEN `scoring_rules` with the pure `Settlement.Engine`,
  persists a `settlement_results` row + a denormalized outcome on the duel, and
  broadcasts `{:duel_settled, ...}`.

  `settle_duel/1` is directly callable (the worker, tests, admin/retry all use
  it). Settlement is idempotent: only a "drafted" duel advances, and the unique
  index on settlement_results.duel_id is a DB-level double-settle guard.
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Contests
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts
  alias HeadsUp.Drafts.Draft
  alias HeadsUp.Settlement.{Engine, Result, Window}
  alias HeadsUp.Sports.Player

  @pubsub HeadsUp.PubSub

  @doc "Drafted duels whose scoring window has closed (worker sweep), users preloaded."
  def due_duels(now \\ DateTime.utc_now()) do
    from(d in Duel,
      where: d.status == "drafted" and not is_nil(d.scoring_window_end) and d.scoring_window_end <= ^now,
      preload: [:challenger, :opponent]
    )
    |> Repo.all()
  end

  @doc "The stored result for a duel (winner preloaded), or nil."
  def get_result(duel_id) do
    Result |> Repo.get_by(duel_id: duel_id) |> Repo.preload(:winner)
  end

  @doc """
  Settle one duel. Returns `{:ok, %Result{}, %Duel{}}` on a fresh settle,
  `{:ok, duel}` if already settled (no-op), or `{:error, reason}`.
  """
  def settle_duel(duel_id) do
    case Repo.get(Duel, duel_id) do
      nil -> {:error, :not_found}
      %Duel{status: "settled"} = duel -> {:ok, duel}
      %Duel{status: "drafted"} = duel -> do_settle(duel)
      %Duel{} -> {:error, :not_drafted}
    end
  end

  defp do_settle(%Duel{} = duel) do
    window = %Window{
      sport: duel.sport,
      opens_at: duel.scoring_window_start,
      closes_at: duel.scoring_window_end,
      duel_id: duel.id
    }

    provider = provider(duel.sport)
    player_ids = Contests.player_ids(duel)

    with true <- provider.stats_final?(window) || {:error, :stats_not_final},
         %Draft{} = draft <- Repo.get_by(Draft, duel_id: duel.id) || {:error, :no_draft},
         [_ | _] = picks <- Drafts.replay(draft.id),
         true <- all_rostered?(picks, player_ids) || {:error, :incomplete_draft},
         players when players != [] <- load_players(picks) do
      stats = provider.fetch_stats(players, window)
      outcome = Engine.settle_ranked(duel.scoring_rules, player_ids, picks, stats)
      persist(duel, outcome, players)
    else
      {:error, reason} -> {:error, reason}
      [] -> {:error, :no_roster}
      false -> {:error, :stats_not_final}
      nil -> {:error, :no_draft}
    end
  end

  @doc """
  LIVE standings for a drafted-but-unsettled duel: both rosters scored against the
  current (possibly in-progress) stats, who's ahead, and a count of in-window
  games by state. Only valid while `status == "drafted"` (before/around the
  scoring window). Returns `{:ok, live}` or `{:error, reason}` (`:not_live` once
  the duel is settled/not drafted — the caller shows the final result instead).
  """
  def live_result(duel_id) do
    case Repo.get(Duel, duel_id) do
      nil -> {:error, :not_found}
      %Duel{status: "drafted"} = duel -> do_live(Repo.preload(duel, [:challenger, :opponent, participants: :user]))
      %Duel{} -> {:error, :not_live}
    end
  end

  defp do_live(%Duel{} = duel) do
    window = %Window{
      sport: duel.sport,
      opens_at: duel.scoring_window_start,
      closes_at: duel.scoring_window_end,
      duel_id: duel.id
    }

    with %Draft{} = draft <- Repo.get_by(Draft, duel_id: duel.id) || {:error, :no_draft},
         [_ | _] = picks <- Drafts.replay(draft.id),
         players when players != [] <- load_players(picks) do
      provider = provider(duel.sport)
      stats = provider.fetch_live_stats(players, window)
      by_user = Enum.group_by(picks, & &1.user_id)
      rules = duel.scoring_rules

      # Every player scored, best total first (stable order for the client).
      sides =
        duel
        |> Contests.player_ids()
        |> Enum.map(&Engine.score_roster(&1, Map.get(by_user, &1, []), stats, rules))
        |> Enum.sort_by(& &1.total, :desc)

      leader_id =
        case sides do
          [a] -> a.user_id
          [a, b | _] when a.total > b.total -> a.user_id
          _ -> nil
        end

      find = fn uid -> Enum.find(sides, &(&1.user_id == uid)) end

      {:ok,
       %{
         duel: duel,
         sides: sides,
         # 1v1 keys kept for the existing matchup screen (nil for groups).
         challenger: duel.opponent_id && find.(duel.challenger_id),
         opponent: duel.opponent_id && find.(duel.opponent_id),
         leader_id: leader_id,
         games: provider.live_games(window),
         team_states: provider.team_states(window),
         players_by_id: Map.new(players, &{&1.id, %{name: &1.name, team: &1.team, position: &1.position}}),
         users_by_id: live_users(duel)
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_roster}
    end
  end

  # id => user for every seat, so the JSON can label any side. Falls back to
  # the 1v1 columns when seat rows predate the participants table.
  defp live_users(%Duel{} = duel) do
    seat_users = for p <- duel.participants || [], p.user, into: %{}, do: {p.user_id, p.user}

    [duel.challenger, duel.opponent]
    |> Enum.reject(&is_nil/1)
    |> Map.new(&{&1.id, &1})
    |> Map.merge(seat_users)
  end

  # A legitimate contest needs every player to have drafted at least one player.
  # One-sided picks (e.g. an upstream auto-pick exhaustion bug) must NOT silently
  # settle as a win — flag it for an operator instead of scoring a forfeit.
  defp all_rostered?(picks, player_ids) do
    by_user = Enum.group_by(picks, & &1.user_id)
    player_ids != [] and Enum.all?(player_ids, &Map.has_key?(by_user, &1))
  end

  defp persist(%Duel{} = duel, outcome, players) do
    by_id = Map.new(players, &{&1.id, &1})
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    is_tie = outcome.result == :tie
    standings = outcome.standings

    # "standings" is the N-player truth; the challenger/opponent keys (and the
    # two Result columns) keep the 1v1 shape every existing screen reads.
    breakdown =
      %{"standings" => Enum.map(standings, &standing_breakdown(&1, by_id))}
      |> Map.merge(role_breakdown(duel, standings, by_id))

    {challenger_points, opponent_points} = result_points(duel, standings)

    result_attrs = %{
      duel_id: duel.id,
      winner_id: outcome.winner_id,
      is_tie: is_tie,
      challenger_points: challenger_points,
      opponent_points: opponent_points,
      settled_at: now,
      breakdown: breakdown
    }

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:result, Result.changeset(%Result{}, result_attrs))
    |> Ecto.Multi.update(
      :duel,
      Duel.settle_changeset(duel, %{status: "settled", winner_id: outcome.winner_id, settled_at: now})
    )
    |> Ecto.Multi.run(:coins, fn repo, _changes ->
      # Escrow → winner (or split across the tied top; a 1v1 tie is exactly
      # both stakes back). Idempotency-keyed, so a double settle can't double-pay.
      HeadsUp.Coins.settle(
        repo,
        duel.id,
        duel.stake_coins,
        Enum.map(standings, &%{user_id: &1.user_id, rank: &1.rank}),
        outcome.winner_id,
        is_tie
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{result: result, duel: settled}} ->
        broadcast(settled, is_tie)
        notify_settled(settled, standings)
        {:ok, result, settled}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp role_breakdown(%Duel{opponent_id: nil}, _standings, _by_id), do: %{}

  defp role_breakdown(%Duel{} = duel, standings, by_id) do
    find = fn uid -> Enum.find(standings, &(&1.user_id == uid)) end

    %{
      "challenger" => roster_breakdown(duel.challenger_id, find.(duel.challenger_id), by_id),
      "opponent" => roster_breakdown(duel.opponent_id, find.(duel.opponent_id), by_id)
    }
  end

  # 1v1 keeps its exact column semantics; a group stores 1st and 2nd place
  # (the "final score line" of the contest).
  defp result_points(%Duel{opponent_id: nil}, standings) do
    [first | rest] = standings
    {first.total, (List.first(rest) || first).total}
  end

  defp result_points(%Duel{} = duel, standings) do
    find = fn uid -> Enum.find(standings, &(&1.user_id == uid)) end
    {find.(duel.challenger_id).total, find.(duel.opponent_id).total}
  end

  # Push the final to every player, framed from each one's seat.
  defp notify_settled(%Duel{} = duel, standings) do
    n = length(standings)

    for s <- standings do
      {title, body} =
        cond do
          n == 2 ->
            other = Enum.find(standings, &(&1.user_id != s.user_id))

            title =
              cond do
                is_nil(duel.winner_id) -> "It's a tie 🤝"
                duel.winner_id == s.user_id -> "You won! 🏆"
                true -> "You lost 😤"
              end

            {title, "Final: #{s.total} – #{other.total}. Tap for the full scoreboard."}

          s.rank == 1 and duel.winner_id == s.user_id ->
            {"You won! 🏆", "1st of #{n} with #{s.total} pts. Tap for the standings."}

          s.rank == 1 ->
            {"Tied for 1st 🤝", "#{s.total} pts. Tap for the standings."}

          true ->
            {"#{ordinal(s.rank)} of #{n} #{rank_emoji(s.rank)}", "#{s.total} pts. Tap for the standings."}
        end

      HeadsUp.Notifications.notify_user(s.user_id, title, body, %{type: "result", duel_id: duel.id})
    end

    :ok
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"

  defp rank_emoji(2), do: "🥈"
  defp rank_emoji(3), do: "🥉"
  defp rank_emoji(_), do: "😤"

  defp standing_breakdown(standing, by_id) do
    standing.user_id
    |> roster_breakdown(standing, by_id)
    |> Map.put("rank", standing.rank)
  end

  defp roster_breakdown(user_id, roster_result, by_id) do
    %{
      "user_id" => user_id,
      "total" => roster_result.total,
      "players" =>
        Enum.map(roster_result.players, fn pr ->
          player = by_id[pr.player_id]

          %{
            "player_id" => pr.player_id,
            "name" => player && player.name,
            "team" => player && player.team,
            "position" => player && player.position,
            "slot" => pr.slot,
            "points" => pr.points,
            "stat_line" => pr.stat_line
          }
        end)
    }
  end

  defp load_players(picks) do
    ids = picks |> Enum.map(& &1.player_id) |> Enum.uniq()
    Repo.all(from p in Player, where: p.id in ^ids)
  end

  defp broadcast(%Duel{} = duel, is_tie) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "duel:#{duel.id}",
      {:duel_settled, %{duel_id: duel.id, status: "settled", winner_id: duel.winner_id, is_tie: is_tie}}
    )
  end

  # Per-sport stats provider: a `:stats_providers` sport=>module map wins, else
  # the single `:stats_provider` default (the Mock in test/base config).
  defp provider(sport) do
    Application.get_env(:heads_up, :stats_providers, %{})
    |> Map.get(sport) || Application.get_env(:heads_up, :stats_provider, HeadsUp.Settlement.Stats.Mock)
  end
end
