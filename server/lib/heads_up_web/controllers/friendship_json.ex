defmodule HeadsUpWeb.FriendshipJSON do
  alias HeadsUpWeb.PublicUserJSON

  @doc "The current user's friends (public user shapes)."
  def friends(%{friends: friends}) do
    %{friends: Enum.map(friends, &PublicUserJSON.public/1)}
  end

  @doc "Incoming pending requests: the friendship id + who sent it."
  def requests(%{requests: requests}) do
    %{
      requests:
        Enum.map(requests, fn f ->
          %{id: f.id, status: f.status, user: PublicUserJSON.public(f.requester)}
        end)
    }
  end

  @doc "A single friendship (after sending or accepting)."
  def show(%{friendship: f}) do
    %{friendship: %{id: f.id, status: f.status}}
  end
end
