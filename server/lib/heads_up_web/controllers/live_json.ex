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
      sides: Enum.map(live.sides, &side(duel.sport, users[&1.user_id], &1, live.players_by_id, uid)),
      # 1v1 keys for the existing matchup screen (absent for group duels).
      challenger: live.challenger && side(duel.sport, duel.challenger, live.challenger, live.players_by_id, uid),
      opponent: live.opponent && side(duel.sport, duel.opponent, live.opponent, live.players_by_id, uid)
    }
  end

  defp side(sport, user, roster, by_id, uid) do
    %{
      user: PublicUserJSON.public(user),
      is_me: user.id == uid,
      total: roster.total,
      players:
        Enum.map(roster.players, fn p ->
          info = Map.get(by_id, p.player_id, %{})

          %{
            player_id: p.player_id,
            name: info[:name],
            team: info[:team],
            position: info[:position],
            slot: p.slot,
            points: p.points,
            stat_line: p.stat_line,
            line: StatLine.format(sport, p.stat_line)
          }
        end)
    }
  end
end
