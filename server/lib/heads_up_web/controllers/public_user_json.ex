defmodule HeadsUpWeb.PublicUserJSON do
  @moduledoc """
  The PUBLIC shape of a user — only id + username, never email or anything
  private. Use this any time we show one user to another (search, friends).
  """

  @doc "Search results: users plus this viewer's relationship to each."
  def search(%{results: results}) do
    %{
      users:
        Enum.map(results, fn %{user: user, relationship: rel, friendship_id: fid} ->
          public(user)
          |> Map.put(:relationship, rel)
          |> Map.put(:friendship_id, fid)
        end)
    }
  end

  def public(user) do
    %{id: user.id, username: user.username}
  end
end
