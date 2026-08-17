defmodule HeadsUpWeb.RivalController do
  use HeadsUpWeb, :controller

  alias HeadsUp.{Repo, Stats}
  alias HeadsUp.Accounts.User

  # GET /api/rivals/:id — one rivalry, whole: the head-to-head tally, the
  # bragging-rights tiles, and the last duels as receipts with story lines.
  def show(conn, %{"id" => id}) do
    me = conn.assigns.current_user

    with {int_id, ""} <- Integer.parse(to_string(id)),
         %User{deleted_at: nil} = rival <- Repo.get(User, int_id) do
      render(conn, :show, rival: rival, rivalry: Stats.rivalry(me.id, rival.id))
    else
      _ ->
        conn |> put_status(:not_found) |> json(%{error: "no such rival"})
    end
  end
end
