defmodule HeadsUpWeb.FriendGroupController do
  @moduledoc """
  CRUD for the viewer's private friend groups — the tabs on the challenge
  screen's recipient list. Every action is scoped to the current user, so a
  group id from someone else's account simply isn't found.
  """
  use HeadsUpWeb, :controller

  alias HeadsUp.Social

  action_fallback HeadsUpWeb.FallbackController

  # GET /api/friend-groups
  def index(conn, _params) do
    json(conn, %{groups: Social.list_friend_groups(conn.assigns.current_user)})
  end

  # POST /api/friend-groups  { "name" }
  def create(conn, %{"name" => name}) do
    with {:ok, group} <- Social.create_friend_group(conn.assigns.current_user, name) do
      conn
      |> put_status(:created)
      |> json(%{group: %{id: group.id, name: group.name, member_ids: []}})
    end
  end

  def create(_conn, _params), do: {:error, "name is required"}

  # PUT /api/friend-groups/:id  { "name" }
  def update(conn, %{"id" => id, "name" => name}) do
    with {:ok, group} <- Social.rename_friend_group(conn.assigns.current_user, id, name) do
      json(conn, %{group: %{id: group.id, name: group.name}})
    end
  end

  def update(_conn, _params), do: {:error, "name is required"}

  # PUT /api/friend-groups/:id/members  { "user_ids": [..] }
  def set_members(conn, %{"id" => id} = params) do
    ids = params |> Map.get("user_ids", []) |> List.wrap() |> Enum.map(&normalize/1) |> Enum.reject(&is_nil/1)

    with {:ok, group} <- Social.set_friend_group_members(conn.assigns.current_user, id, ids) do
      json(conn, %{group: group})
    end
  end

  # DELETE /api/friend-groups/:id
  def delete(conn, %{"id" => id}) do
    with {:ok, _} <- Social.delete_friend_group(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp normalize(id) when is_integer(id), do: id

  defp normalize(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp normalize(_), do: nil
end
