defmodule HeadsUpWeb.ResultJSON do
  @moduledoc """
  The settled scoreboard from the current user's point of view: both lineups
  (per-player points + stat lines), team totals, and the outcome (win/loss/tie).
  Reads the frozen role-keyed breakdown stored on the settlement_results row.
  """
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Settlement.Result

  def show(%{result: result, duel: duel, current_user_id: uid}) do
    %{result: data(result, duel, uid)}
  end

  def data(%Result{} = result, %Duel{} = duel, uid) do
    outcome =
      cond do
        result.is_tie -> "tie"
        result.winner_id == uid -> "win"
        true -> "loss"
      end

    %{
      duel_id: duel.id,
      status: duel.status,
      is_tie: result.is_tie,
      winner_id: result.winner_id,
      my_outcome: outcome,
      settled_at: result.settled_at,
      # Ranked standings (all contests; the only shape group duels have).
      standings: standings(result, duel, uid),
      challenger: lineup(result.breakdown["challenger"], duel.challenger_id, uid),
      opponent: lineup(result.breakdown["opponent"], duel.opponent_id, uid)
    }
  end

  # Standings stored at settle time, joined to usernames via the duel's seats.
  defp standings(%Result{breakdown: breakdown}, duel, uid) do
    names =
      case duel.participants do
        seats when is_list(seats) -> for p <- seats, p.user, into: %{}, do: {p.user_id, p.user.username}
        _ -> %{}
      end

    for s <- breakdown["standings"] || [] do
      s
      |> lineup(s["user_id"], uid)
      |> Map.put(:rank, s["rank"])
      |> Map.put(:username, Map.get(names, s["user_id"]))
    end
  end

  defp lineup(role, user_id, uid) do
    role = role || %{}

    players =
      for p <- role["players"] || [] do
        %{
          player_id: p["player_id"],
          name: p["name"],
          team: p["team"],
          position: p["position"],
          slot: p["slot"],
          points: round1(p["points"]),
          stat_line: p["stat_line"] || %{}
        }
      end

    %{
      user_id: user_id,
      is_me: user_id == uid,
      # Sum the displayed (rounded) player points so the team total always equals
      # what's shown on the scoreboard (no 0.1 rounding drift).
      total: players |> Enum.reduce(0.0, fn p, acc -> acc + p.points end) |> round1(),
      players: players
    }
  end

  defp round1(n) when is_number(n), do: Float.round(n * 1.0, 1)
  defp round1(_), do: 0.0
end
