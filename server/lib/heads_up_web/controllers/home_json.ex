defmodule HeadsUpWeb.HomeJSON do
  alias HeadsUpWeb.DuelJSON

  def index(%{summary: s, current_user_id: uid}) do
    %{
      needs_response: duels(s.needs_response, uid),
      waiting_on_them: duels(s.waiting_on_them, uid),
      draft_ready: duels(s.draft_ready, uid),
      awaiting: duels(s.awaiting, uid),
      recent_results: duels(s.recent_results, uid),
      record: record(s.record)
    }
  end

  defp duels(list, uid), do: Enum.map(list, &DuelJSON.data(&1, uid))

  defp record(r) do
    %{
      wins: r.wins,
      losses: r.losses,
      ties: r.ties,
      played: r.played,
      win_pct: r.win_pct,
      streak: r.streak,
      recent: r.recent
    }
  end
end
