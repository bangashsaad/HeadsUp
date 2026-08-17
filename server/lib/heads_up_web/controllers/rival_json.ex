defmodule HeadsUpWeb.RivalJSON do
  alias HeadsUpWeb.PublicUserJSON

  def show(%{rival: rival, rivalry: r}) do
    %{
      rival: PublicUserJSON.public(rival),
      rivalry: %{
        wins: r.wins,
        losses: r.losses,
        ties: r.ties,
        played: r.played,
        form: r.form,
        run: r.run,
        avg_margin: r.avg_margin,
        best_win: r.best_win,
        history:
          Enum.map(r.history, fn h ->
            %{
              outcome: h.outcome,
              my_points: h.my_points,
              their_points: h.their_points,
              settled_at: h.settled_at,
              story: h.story
            }
          end)
      }
    }
  end
end
