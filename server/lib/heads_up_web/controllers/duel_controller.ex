defmodule HeadsUpWeb.DuelController do
  use HeadsUpWeb, :controller

  alias HeadsUp.{Contests, Settlement}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Settlement.Result

  plug :put_view, json: HeadsUpWeb.DuelJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/duels
  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, duels: Contests.list_duels(user), current_user_id: user.id)
  end

  # GET /api/duels/:id
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Contests.get_duel(user, id) do
      nil -> {:error, :not_found}
      duel -> render(conn, :show, duel: duel, current_user_id: user.id)
    end
  end

  # GET /api/duels/:id/result  (the settled scoreboard)
  def result(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with %Duel{} = duel <- Contests.get_duel(user, id),
         %Result{} = result <- Settlement.get_result(duel.id) do
      conn
      |> put_view(json: HeadsUpWeb.ResultJSON)
      |> render(:show, result: result, duel: duel, current_user_id: user.id)
    else
      _ -> {:error, :not_found}
    end
  end

  # GET /api/duels/:id/live  (live standings before the duel settles)
  def live(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Contests.get_duel(user, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})

      %Duel{} ->
        case Settlement.live_result(id) do
          {:ok, live} ->
            conn |> put_view(json: HeadsUpWeb.LiveJSON) |> render(:show, live: live, current_user_id: user.id)

          # Not drafted yet / already settled → tell the client to fall back.
          {:error, reason} ->
            conn |> put_status(:conflict) |> json(%{error: "not live", reason: to_string(reason)})
        end
    end
  end

  # POST /api/duels
  def create(conn, params) do
    user = conn.assigns.current_user

    with {:ok, duel} <- Contests.create_challenge(user, params) do
      conn
      |> put_status(:created)
      |> render(:show, duel: duel, current_user_id: user.id)
    end
  end

  # POST /api/duels/:id/accept
  def accept(conn, %{"id" => id}) do
    act(conn, &Contests.accept_challenge/2, id)
  end

  # POST /api/duels/:id/decline
  def decline(conn, %{"id" => id}) do
    act(conn, &Contests.decline_challenge/2, id)
  end

  # POST /api/duels/:id/cancel
  def cancel(conn, %{"id" => id}) do
    act(conn, &Contests.cancel_challenge/2, id)
  end

  # POST /api/duels/:id/counter  (body: new terms)
  def counter(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    terms = Map.drop(params, ["id"])

    with {:ok, duel} <- Contests.counter_challenge(user, id, terms) do
      conn
      |> put_status(:created)
      |> render(:show, duel: duel, current_user_id: user.id)
    end
  end

  # POST /api/duels/:id/rematch — clone terms into a new challenge to the same opponent
  def rematch(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, duel} <- Contests.rematch(user, id, Map.drop(params, ["id"])) do
      conn
      |> put_status(:created)
      |> render(:show, duel: duel, current_user_id: user.id)
    end
  end

  defp act(conn, fun, id) do
    user = conn.assigns.current_user

    with {:ok, duel} <- fun.(user, id) do
      render(conn, :show, duel: duel, current_user_id: user.id)
    end
  end
end
