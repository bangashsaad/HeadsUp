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

    with true <- provider.stats_final?(window) || {:error, :stats_not_final},
         %Draft{} = draft <- Repo.get_by(Draft, duel_id: duel.id) || {:error, :no_draft},
         [_ | _] = picks <- Drafts.replay(draft.id),
         true <- both_rostered?(picks, duel) || {:error, :incomplete_draft},
         players when players != [] <- load_players(picks) do
      stats = provider.fetch_stats(players, window)
      outcome = Engine.settle(duel, picks, stats)
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
      %Duel{status: "drafted"} = duel -> do_live(Repo.preload(duel, [:challenger, :opponent]))
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

      challenger = Engine.score_roster(duel.challenger_id, Map.get(by_user, duel.challenger_id, []), stats, rules)
      opponent = Engine.score_roster(duel.opponent_id, Map.get(by_user, duel.opponent_id, []), stats, rules)

      leader_id =
        cond do
          challenger.total > opponent.total -> duel.challenger_id
          opponent.total > challenger.total -> duel.opponent_id
          true -> nil
        end

      {:ok,
       %{
         duel: duel,
         challenger: challenger,
         opponent: opponent,
         leader_id: leader_id,
         games: provider.live_games(window),
         players_by_id: Map.new(players, &{&1.id, %{name: &1.name, team: &1.team, position: &1.position}})
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_roster}
    end
  end

  # A legitimate matchup needs both players to have drafted at least one player.
  # One-sided picks (e.g. an upstream auto-pick exhaustion bug) must NOT silently
  # settle as a win — flag it for an operator instead of scoring a forfeit.
  defp both_rostered?(picks, %Duel{challenger_id: c, opponent_id: o}) do
    by_user = Enum.group_by(picks, & &1.user_id)
    Map.has_key?(by_user, c) and Map.has_key?(by_user, o)
  end

  defp persist(%Duel{} = duel, outcome, players) do
    by_id = Map.new(players, &{&1.id, &1})
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    is_tie = outcome.result == :tie

    breakdown = %{
      "challenger" => roster_breakdown(duel.challenger_id, outcome.challenger, by_id),
      "opponent" => roster_breakdown(duel.opponent_id, outcome.opponent, by_id)
    }

    result_attrs = %{
      duel_id: duel.id,
      winner_id: outcome.winner_id,
      is_tie: is_tie,
      challenger_points: outcome.challenger.total,
      opponent_points: outcome.opponent.total,
      settled_at: now,
      breakdown: breakdown
    }

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:result, Result.changeset(%Result{}, result_attrs))
    |> Ecto.Multi.update(
      :duel,
      Duel.settle_changeset(duel, %{status: "settled", winner_id: outcome.winner_id, settled_at: now})
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{result: result, duel: settled}} ->
        broadcast(settled, is_tie)
        {:ok, result, settled}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
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
