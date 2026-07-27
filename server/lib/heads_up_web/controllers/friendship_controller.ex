defmodule HeadsUpWeb.FriendshipController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Social

  plug :put_view, json: HeadsUpWeb.FriendshipJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/friends  -> my accepted friends
  def index(conn, _params) do
    friends = Social.list_friends(conn.assigns.current_user)
    render(conn, :friends, friends: friends)
  end

  # GET /api/friends/requests  -> pending requests sent to me
  def requests(conn, _params) do
    requests = Social.list_incoming_requests(conn.assigns.current_user)
    render(conn, :requests, requests: requests)
  end

  # POST /api/friends  { "user_id": 2 }  -> send a request
  def create(conn, %{"user_id" => user_id}) do
    with {:ok, friendship} <- Social.send_friend_request(conn.assigns.current_user, user_id) do
      conn
      |> put_status(:created)
      |> render(:show, friendship: friendship)
    end
  end

  def create(_conn, _params), do: {:error, "user_id is required"}

  # POST /api/friends/requests/:id/accept
  def accept(conn, %{"id" => id}) do
    with {:ok, friendship} <- Social.accept_friend_request(conn.assigns.current_user, id) do
      render(conn, :show, friendship: friendship)
    end
  end

  # DELETE /api/friends/requests/:id  -> decline / cancel / unfriend
  def delete(conn, %{"id" => id}) do
    with :ok <- Social.delete_friendship(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
