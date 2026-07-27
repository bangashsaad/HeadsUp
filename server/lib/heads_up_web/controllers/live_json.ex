defmodule HeadsUpWeb.LiveJSON do
  alias HeadsUpWeb.PublicUserJSON
  alias HeadsUp.Sports.StatLine

  def show(%{live: live, current_user_id: uid}) do
    duel = live.duel
    users = live.users_by_id

    %{
      duel_id: duel.id,
      status: duel.status,
      sport: duel.sport,
      leader_id: live.leader_id,
      games: live.games,
      # Every seat scored, best total first — the N-player standings strip.
      sides: Enum.map(live.sides, &side(duel.sport, users[&1.user_id], &1, live, uid)),
      # 1v1 keys for the existing matchup screen (absent for group duels).
      challenger: live.challenger && side(duel.sport, duel.challenger, live.challenger, live, uid),
      opponent: live.opponent && side(duel.sport, duel.opponent, live.opponent, live, uid)
    }
  end

  defp side(sport, user, roster, live, uid) do
    team_states = Map.get(live, :team_states) || %{}

    %{
      user: PublicUserJSON.public(user),
      is_me: user.id == uid,
      total: roster.total,
      players:
        Enum.map(roster.players, fn p ->
          info = Map.get(live.players_by_id, p.player_id, %{})

          %{
            player_id: p.player_id,
            name: info[:name],
            team: info[:team],
            position: info[:position],
            slot: p.slot,
            points: p.points,
            stat_line: p.stat_line,
            line: StatLine.format(sport, p.stat_line),
            # The player's game right now: %{state: "pre"|"in"|"post", detail: "End of 1st"}.
            game: info[:team] && Map.get(team_states, info[:team])
          }
        end)
    }
  end
end
