defmodule HeadsUpWeb.UserController do
  use HeadsUpWeb, :controller

  alias HeadsUp.{Social, Stats}

  plug :put_view, json: HeadsUpWeb.PublicUserJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/users/search?q=...
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
      render(conn, :profile, profile: profile, record: Stats.record_for(id), vs_you: vs_you)
    else
      _ -> {:error, :not_found}
    end
  end
end
