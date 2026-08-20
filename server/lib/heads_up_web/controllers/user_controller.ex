defmodule HeadsUpWeb.UserController do
  use HeadsUpWeb, :controller

  alias HeadsUp.{Social, Stats}

  plug :put_view, json: HeadsUpWeb.PublicUserJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/users/search?q=...
  # POST /api/users/:id/block   DELETE /api/users/:id/block
  def block(conn, %{"id" => id}) do
    with {:ok, _} <- HeadsUp.Social.block_user(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end

  def unblock(conn, %{"id" => id}) do
    with {uid, ""} <- Integer.parse(to_string(id)),
         :ok <- HeadsUp.Social.unblock_user(conn.assigns.current_user, uid) do
      send_resp(conn, :no_content, "")
    end
  end

  # GET /api/blocks
  def blocked(conn, _params) do
    users = HeadsUp.Social.list_blocked(conn.assigns.current_user)
    json(conn, %{blocked: Enum.map(users, &HeadsUpWeb.PublicUserJSON.public/1)})
  end

  def search(conn, params) do
    query = Map.get(params, "q", "")
    results = Social.search_users(query, conn.assigns.current_user)
    render(conn, :search, results: results)
  end

  # GET /api/users/:id — a tappable public profile: relationship + W/L record
  # + the viewer's head-to-head vs them. How you add a friend from a game.
  def show(conn, %{"id" => raw_id}) do
    viewer = conn.assigns.current_user

    with {id, ""} <- Integer.parse(to_string(raw_id)),
         {:ok, profile} <- Social.public_profile(viewer, id) do
      vs_you = Enum.find(Stats.head_to_head(viewer.id), &(&1.opponent.id == id))

      render(conn, :profile,
        profile: profile,
        record: Stats.record_for(id),
        vs_you: vs_you,
        history: Stats.history_vs(viewer.id, id)
      )
    else
      _ -> {:error, :not_found}
    end
  end
end
